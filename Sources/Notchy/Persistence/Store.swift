import Foundation
import Combine

/// Local-first JSON store in ~/Library/Application Support/Notchy. The folder name stays
/// put so a display-name change does not orphan existing data. Nothing leaves the Mac
/// unless the user turns on Reminders sync or exports a backup.
@MainActor
final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { scheduleSave() } }
    @Published var sessions: [FocusSession] = [] { didSet { scheduleSave() } }
    @Published var clips: [Clip] = [] { didSet { scheduleSave() } }
    @Published var notes: [String: String] = [:] { didSet { scheduleSave() } }
    @Published var settings = AppSettings() { didSet { scheduleSave() } }
    @Published var deletedReminderIDs: [String] = [] { didSet { scheduleSave() } }
    @Published var appleNoteLinks: [String: AppleNoteLink] = [:] { didSet { scheduleSave() } }

    let fileURL: URL
    private var isApplying = false
    private var saveWork: DispatchWorkItem?

    init(fileURL: URL = Store.defaultDataURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: Locations

    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static var defaultDataURL: URL { supportDirectory.appendingPathComponent("data.json") }

    nonisolated static var clipsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    nonisolated static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    // MARK: Persistence

    var snapshot: AppData {
        var d = AppData()
        d.tasks = tasks
        d.sessions = sessions
        d.clips = clips
        d.notes = notes
        d.settings = settings
        d.deletedReminderIDs = deletedReminderIDs
        d.appleNoteLinks = appleNoteLinks
        return d
    }

    private func apply(_ data: AppData, keepSettings: Bool = false) {
        isApplying = true
        tasks = data.tasks
        sessions = data.sessions
        clips = data.clips
        notes = data.notes
        if !keepSettings { settings = data.settings }
        deletedReminderIDs = data.deletedReminderIDs
        appleNoteLinks = data.appleNoteLinks
        isApplying = false
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            apply(try Self.makeDecoder().decode(AppData.self, from: data))
        } catch {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("data.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func scheduleSave() {
        guard !isApplying else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do {
            let data = try Self.makeEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("HappyNotch: failed to save data: \(error)")
        }
    }

    func exportData(to url: URL) throws {
        var data = snapshot
        data.exportedAt = Date()
        data.settings.mcpToken = ""
        data.appleNoteLinks = [:]
        try Self.makeEncoder(pretty: true).encode(data).write(to: url, options: [.atomic])
    }

    func importData(from url: URL) throws {
        let data = try Self.makeDecoder().decode(AppData.self, from: Data(contentsOf: url))
        apply(data, keepSettings: true)
        saveNow()
    }

    func eraseAll() {
        for clip in clips {
            try? FileManager.default.removeItem(at: Self.clipsDirectory.appendingPathComponent(clip.fileName))
        }
        var fresh = AppData()
        fresh.settings = settings
        fresh.settings.remindersSyncEnabled = false
        fresh.settings.appleNotesSyncEnabled = false
        apply(fresh, keepSettings: false)
        saveNow()
    }

    // MARK: Tasks

    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    @discardableResult
    func addTask(text: String, defaultDay: Date? = nil) -> TaskItem? {
        let parsed = NaturalLanguageParser.parse(text)
        guard !parsed.title.isEmpty else { return nil }
        var task = TaskItem(title: parsed.title)
        if let due = parsed.dueDate {
            task.dueDate = due
            task.hasTime = parsed.hasTime
        } else if let defaultDay {
            task.dueDate = Calendar.current.startOfDay(for: defaultDay)
        }
        task.priority = parsed.priority
        task.sortIndex = (tasks.map(\.sortIndex).max() ?? 0) + 1
        tasks.append(task)
        return task
    }

    func updateTask(_ id: UUID, _ mutate: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[index]
        let previousDue = task.dueDate
        let previousHasTime = task.hasTime
        mutate(&task)
        if task.dueDate != previousDue || task.hasTime != previousHasTime { task.reminderFired = false }
        task.lastModified = Date()
        tasks[index] = task
    }

    func setCompleted(_ id: UUID, _ completed: Bool) {
        updateTask(id) {
            $0.isCompleted = completed
            $0.completedAt = completed ? Date() : nil
        }
    }

    func toggleComplete(_ id: UUID) {
        guard let task = task(id) else { return }
        setCompleted(id, !task.isCompleted)
    }

    func deleteTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let rid = tasks[index].reminderIdentifier { deletedReminderIDs.append(rid) }
        tasks.remove(at: index)
    }

    /// Moves `id` directly before `target` in manual sort order.
    func moveTask(_ id: UUID, before target: UUID) {
        let ordered = tasks.sorted { $0.sortIndex < $1.sortIndex }
        guard let targetIndex = ordered.firstIndex(where: { $0.id == target }) else { return }
        let upper = ordered[targetIndex].sortIndex
        let lower = ordered[..<targetIndex].last(where: { $0.id != id })?.sortIndex ?? (upper - 2)
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].sortIndex = (lower + upper) / 2
        tasks[index].lastModified = Date()
    }

    /// Moves a task to `day`, keeping its time of day; `nil` clears the date.
    func reschedule(_ id: UUID, to day: Date?) {
        let cal = Calendar.current
        updateTask(id) { task in
            guard let day else {
                task.dueDate = nil
                task.hasTime = false
                return
            }
            let start = cal.startOfDay(for: day)
            if task.hasTime, let due = task.dueDate {
                let time = cal.dateComponents([.hour, .minute], from: due)
                task.dueDate = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: start)
            } else {
                task.dueDate = start
            }
        }
    }

    /// Tasks for a day: open tasks due that day (plus overdue and undated ones when the day is
    /// today), or tasks completed on that day.
    func tasks(on day: Date, completed: Bool) -> [TaskItem] {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let startOfDay = cal.startOfDay(for: day)
        return tasks.filter { task in
            if completed {
                guard task.isCompleted, let done = task.completedAt else { return false }
                return cal.isDate(done, inSameDayAs: day)
            }
            guard !task.isCompleted else { return false }
            guard let due = task.dueDate else { return isToday }
            if cal.isDate(due, inSameDayAs: day) { return true }
            return isToday && due < startOfDay
        }
        .sorted { $0.sortIndex < $1.sortIndex }
    }

    // MARK: Notes

    func note(for day: Date) -> String { notes[DayKey.key(for: day)] ?? "" }

    func setNote(_ text: String, for day: Date) {
        let key = DayKey.key(for: day)
        if text.isEmpty {
            if notes[key] != nil { notes[key] = nil }
        } else if notes[key] != text {
            notes[key] = text
        }
    }

    // MARK: Focus

    func recordFocus(taskID: UUID?, start: Date, duration: TimeInterval) {
        guard duration >= 30 else { return }
        let title = taskID.flatMap { task($0)?.title }
        sessions.append(FocusSession(taskID: taskID, taskTitle: title, start: start, duration: duration))
        if let taskID, let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].focusedSeconds += duration
        }
    }
}
