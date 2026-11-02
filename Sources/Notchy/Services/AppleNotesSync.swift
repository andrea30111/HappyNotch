import AppKit
import Combine
import Foundation

/// Opt-in two-way sync between the daily notepad and a "Notchy" folder in Apple Notes.
/// Notes has no public framework, so this goes through AppleScript (Automation permission).
/// Each day becomes one note titled "Notchy · yyyy-MM-dd"; other notes are never touched.
@MainActor
final class AppleNotesSync: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var needsPermission = false
    @Published var lastError: String?

    private let store: Store
    private var pending: DispatchWorkItem?
    private var pendingLaunchesNotes = false
    private var resync: Bool?
    private var cancellables = Set<AnyCancellable>()

    init(store: Store) {
        self.store = store
        store.$notes.dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleSync(after: 0, launchingNotes: true) }
            .store(in: &cancellables)
        Timer.publish(every: 60, tolerance: 10, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.scheduleSync(after: 0, launchingNotes: false) }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier }
            .filter { $0 == NotesScript.bundleIdentifier }
            .sink { [weak self] _ in self?.scheduleSync(after: 0.5, launchingNotes: false) }
            .store(in: &cancellables)
        if isEnabled { scheduleSync(after: 3, launchingNotes: true) }
    }

    var isEnabled: Bool { store.settings.appleNotesSyncEnabled }

    func setEnabled(_ enabled: Bool) {
        store.settings.appleNotesSyncEnabled = enabled
        if enabled {
            needsPermission = false
            lastError = nil
            scheduleSync(after: 0.1, launchingNotes: true)
        } else {
            pending?.cancel()
            lastError = nil
            needsPermission = false
        }
    }

    /// Pulls changes made in Notes (e.g. when the panel opens) if Notes is running and no sync just ran.
    func refreshIfStale() {
        guard isEnabled, (lastSync.map { Date().timeIntervalSince($0) > 20 } ?? true) else { return }
        scheduleSync(after: 0.3, launchingNotes: false)
    }

    /// `launchingNotes` starts Notes hidden when it isn't running; background refreshes leave it closed.
    func scheduleSync(after delay: TimeInterval, launchingNotes: Bool) {
        guard isEnabled else { return }
        if isSyncing {
            resync = (resync ?? false) || launchingNotes
            return
        }
        pending?.cancel()
        let launch = launchingNotes || pendingLaunchesNotes
        pendingLaunchesNotes = launch
        let work = DispatchWorkItem { [weak self] in
            self?.pendingLaunchesNotes = false
            Task { await self?.sync(launchingNotes: launch) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func isLinked(_ day: Date) -> Bool { store.appleNoteLinks[DayKey.key(for: day)] != nil }

    func openInNotes(_ day: Date) {
        guard let id = store.appleNoteLinks[DayKey.key(for: day)]?.noteID else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
            return
        }
        Task {
            do {
                try await NotesScript.show(id: id)
            } catch {
                report(error)
            }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Sync

    func sync(launchingNotes: Bool = true) async {
        guard isEnabled, !isSyncing else { return }
        if !NotesScript.isRunning {
            guard launchingNotes else { return }
            guard await NotesScript.launchHidden() else {
                lastError = "Couldn't start Notes."
                return
            }
        }
        isSyncing = true
        defer {
            isSyncing = false
            if let launch = resync {
                resync = nil
                scheduleSync(after: 1, launchingNotes: launch)
            }
        }

        let remote: [NotesScript.RemoteNote]
        do {
            remote = try await NotesScript.fetch()
            needsPermission = false
        } catch {
            report(error)
            return
        }
        var byID: [String: NotesScript.RemoteNote] = [:]
        var byDay: [String: NotesScript.RemoteNote] = [:]
        for note in remote {
            byID[note.id] = note
            if let day = note.day, byDay[day] == nil { byDay[day] = note }
        }

        let days = Set(store.notes.keys).union(store.appleNoteLinks.keys).union(byDay.keys)
        var errors: [String] = []
        for day in days.sorted() {
            do {
                try await reconcile(day: day, byID: byID, byDay: byDay)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        lastError = errors.first
        lastSync = Date()
    }

    private func reconcile(day: String, byID: [String: NotesScript.RemoteNote], byDay: [String: NotesScript.RemoteNote]) async throws {
        let local = store.notes[day] ?? ""
        let link = store.appleNoteLinks[day]
        let note = link.flatMap { byID[$0.noteID] } ?? byDay[day]

        switch (link, note) {
        case (let link?, nil):
            // Deleted in Notes: follow it unless the day was edited here since the last sync.
            if local == link.localText {
                setLocal(nil, day: day, expected: local)
                store.appleNoteLinks[day] = nil
            } else if !local.isEmpty {
                let id = try await NotesScript.create(day: day, text: local)
                store.appleNoteLinks[day] = AppleNoteLink(noteID: id, localText: local, remoteText: nil)
            } else {
                store.appleNoteLinks[day] = nil
            }

        case (let link?, let note?):
            let localChanged = local != link.localText
            let remoteChanged = link.remoteText.map { $0 != note.text } ?? false
            if localChanged && local.isEmpty && !remoteChanged {
                try await NotesScript.delete(id: note.id)
                store.appleNoteLinks[day] = nil
            } else if localChanged {
                try await NotesScript.update(id: note.id, day: day, text: local)
                store.appleNoteLinks[day] = AppleNoteLink(noteID: note.id, localText: local, remoteText: nil)
            } else if remoteChanged {
                if setLocal(note.text, day: day, expected: local) {
                    store.appleNoteLinks[day] = AppleNoteLink(noteID: note.id, localText: note.text, remoteText: note.text)
                }
            } else if link.remoteText == nil || link.noteID != note.id {
                store.appleNoteLinks[day] = AppleNoteLink(noteID: note.id, localText: local, remoteText: note.text)
            }

        case (nil, let note?):
            let merged = Self.merge(local: local, remote: note.text)
            if merged != note.text {
                try await NotesScript.update(id: note.id, day: day, text: merged)
            }
            if setLocal(merged, day: day, expected: local) {
                store.appleNoteLinks[day] = AppleNoteLink(noteID: note.id, localText: merged, remoteText: merged == note.text ? note.text : nil)
            }

        case (nil, nil):
            guard !local.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let id = try await NotesScript.create(day: day, text: local)
            store.appleNoteLinks[day] = AppleNoteLink(noteID: id, localText: local, remoteText: nil)
        }
    }

    /// Writes a day's note unless the user edited it while AppleScript was running.
    @discardableResult
    private func setLocal(_ text: String?, day: String, expected: String) -> Bool {
        guard (store.notes[day] ?? "") == expected else { return false }
        let value = text ?? ""
        if value.isEmpty {
            if store.notes[day] != nil { store.notes[day] = nil }
        } else if store.notes[day] != value {
            store.notes[day] = value
        }
        return true
    }

    /// Joins a local note and an unlinked Notes note for the same day without losing either.
    nonisolated static func merge(local: String, remote: String) -> String {
        let l = NotesScript.normalize(local)
        let r = remote
        if l.isEmpty || l == r || r.contains(l) { return r }
        if r.isEmpty || l.contains(r) { return l }
        return l + "\n\n" + r
    }

    private func report(_ error: Error) {
        if let scriptError = error as? NotesScript.ScriptError, scriptError.isPermissionDenied {
            needsPermission = true
            lastError = "Allow HappyNotch to control Notes in System Settings › Privacy & Security › Automation."
        } else {
            lastError = error.localizedDescription
        }
    }
}

/// AppleScript bridge to Notes, run through `/usr/bin/osascript` one script at a time.
/// Scripts are ASCII-only; every user string is passed as an argument so encoding never matters.
enum NotesScript {
    static let folder = "Notchy"
    static let bundleIdentifier = "com.apple.Notes"
    private static let queue = DispatchQueue(label: "app.notchy.notes-script", qos: .utility)
    private static let recordSeparator = "\u{1E}"
    private static let unitSeparator = "\u{1F}"

    struct RemoteNote: Sendable {
        let id: String
        let name: String
        /// Normalized body without the title line.
        let text: String
        var day: String? { NotesScript.day(fromTitle: name) }
    }

    struct ScriptError: LocalizedError {
        let number: Int
        let message: String
        var isPermissionDenied: Bool { number == -1743 || number == -1744 }
        var errorDescription: String? { "Notes: \(message)" }
    }

    // MARK: Text

    static func title(for day: String) -> String { "Notchy · \(day)" }

    static func day(fromTitle title: String) -> String? {
        guard title.hasPrefix("Notchy"),
              let range = title.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let key = String(title[range])
        return DayKey.date(from: key) == nil ? nil : key
    }

    /// Notes returns non-breaking spaces and CR line breaks; compare text in one canonical form.
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    /// Body of a note's plaintext without its first (title) line.
    static func body(fromPlaintext plaintext: String) -> String {
        let text = normalize(plaintext)
        guard let newline = text.firstIndex(of: "\n") else { return "" }
        return normalize(String(text[text.index(after: newline)...]))
    }

    static func html(day: String, text: String) -> String {
        var parts = ["<div><h1>\(escapeHTML(title(for: day)))</h1></div>"]
        for line in normalize(text).components(separatedBy: "\n") {
            parts.append(line.isEmpty ? "<div><br></div>" : "<div>\(escapeHTML(line))</div>")
        }
        return parts.joined()
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Parses the `fetch` script output: records separated by RS, fields (id, name, plaintext) by US.
    static func parseFetchOutput(_ output: String) -> [RemoteNote] {
        output.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: unitSeparator)
            guard fields.count >= 3, !fields[0].isEmpty else { return nil }
            let text = fields[2...].joined(separator: unitSeparator)
            return RemoteNote(id: fields[0], name: fields[1], text: body(fromPlaintext: text))
        }
    }

    // MARK: Notes app

    @MainActor
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Starts Notes in the background without showing or activating it.
    @MainActor
    static func launchHidden() async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<40 where !app.isFinishedLaunching {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Scripts

    private static let ensureFolder = """
        set acc to default account
        if not (exists folder folderName of acc) then make new folder at acc with properties {name:folderName}
        set f to folder folderName of acc
    """

    static func fetch() async throws -> [RemoteNote] {
        let output = try await run("""
        on run argv
            set folderName to item 1 of argv
            set RS to character id 30
            set US to character id 31
            tell application "Notes"
        \(ensureFolder)
                set theIDs to id of every note of f
                set theNames to name of every note of f
                set theTexts to plaintext of every note of f
            end tell
            set out to {}
            repeat with i from 1 to count of theIDs
                set end of out to (item i of theIDs) & US & (item i of theNames) & US & (item i of theTexts)
            end repeat
            set AppleScript's text item delimiters to RS
            set joined to out as text
            set AppleScript's text item delimiters to ""
            return joined
        end run
        """, arguments: [folder])
        return parseFetchOutput(output)
    }

    static func create(day: String, text: String) async throws -> String {
        let id = try await run("""
        on run argv
            set folderName to item 1 of argv
            set noteBody to item 2 of argv
            tell application "Notes"
        \(ensureFolder)
                set n to make new note at f with properties {body:noteBody}
                return id of n
            end tell
        end run
        """, arguments: [folder, html(day: day, text: text)])
        guard !id.isEmpty else { throw ScriptError(number: 0, message: "Couldn't create the note.") }
        return id
    }

    static func update(id: String, day: String, text: String) async throws {
        try await run("""
        on run argv
            tell application "Notes" to set body of note id (item 1 of argv) to (item 2 of argv)
        end run
        """, arguments: [id, html(day: day, text: text)])
    }

    static func delete(id: String) async throws {
        try await run("""
        on run argv
            tell application "Notes" to delete note id (item 1 of argv)
        end run
        """, arguments: [id])
    }

    static func show(id: String) async throws {
        try await run("""
        on run argv
            tell application "Notes"
                show note id (item 1 of argv)
                activate
            end tell
        end run
        """, arguments: [id])
    }

    /// Runs an AppleScript with `osascript` and returns its result as text (trailing newline removed).
    @discardableResult
    static func run(_ source: String, arguments: [String] = [], timeout: TimeInterval = 150) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = source.components(separatedBy: "\n").flatMap { ["-e", $0] } + arguments
                var environment = ProcessInfo.processInfo.environment
                environment["LANG"] = "en_US.UTF-8"
                environment["LC_ALL"] = "en_US.UTF-8"
                process.environment = environment
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ScriptError(number: 0, message: error.localizedDescription))
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                var errorData = Data()
                let errorReader = DispatchGroup()
                errorReader.enter()
                DispatchQueue.global().async {
                    errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    errorReader.leave()
                }
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errorReader.wait()
                watchdog.cancel()

                var output = String(decoding: outputData, as: UTF8.self)
                if output.hasSuffix("\n") { output.removeLast() }
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: parseError(String(decoding: errorData, as: UTF8.self), timedOut: process.terminationReason == .uncaughtSignal))
                    return
                }
                continuation.resume(returning: output)
            }
        }
    }

    static func parseError(_ stderr: String, timedOut: Bool = false) -> ScriptError {
        if timedOut { return ScriptError(number: -1712, message: "Notes didn't respond in time.") }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        var number = 0
        if let range = trimmed.range(of: #"\((-?\d+)\)$"#, options: .regularExpression) {
            number = Int(trimmed[range].dropFirst().dropLast()) ?? 0
        }
        var message = trimmed
        if let range = message.range(of: "execution error: ") { message = String(message[range.upperBound...]) }
        if let range = message.range(of: #"\s*\(-?\d+\)$"#, options: .regularExpression) { message.removeSubrange(range) }
        return ScriptError(number: number, message: message.isEmpty ? "AppleScript failed." : message)
    }
}
