import Foundation
import Security

enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case none = 0, low, medium, high

    var id: Int { rawValue }
    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case countdown, stopwatch
    var id: String { rawValue }
    var label: String { self == .countdown ? "Countdown" : "Stopwatch" }
}

enum HotKeyPreset: String, Codable, CaseIterable, Identifiable {
    case optionN, controlOptionN, commandShiftN, optionSpace
    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionN: return "⌥N"
        case .controlOptionN: return "⌃⌥N"
        case .commandShiftN: return "⇧⌘N"
        case .optionSpace: return "⌥Space"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var dueDate: Date?
    var hasTime: Bool = false
    var priority: Priority = .none
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    var sortIndex: Double = 0
    var focusedSeconds: TimeInterval = 0
    var reminderFired: Bool = false
    var reminderIdentifier: String?
    var syncedAt: Date?

    var reminderDate: Date? { hasTime ? dueDate : nil }

    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return hasTime ? dueDate < now : dueDate < calendar.startOfDay(for: now)
    }
}

extension TaskItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
        focusedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .focusedSeconds) ?? 0
        reminderFired = try c.decodeIfPresent(Bool.self, forKey: .reminderFired) ?? false
        reminderIdentifier = try c.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}

struct FocusSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var taskID: UUID?
    var taskTitle: String?
    var start: Date
    var duration: TimeInterval
}

struct Clip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var createdAt: Date = Date()
}

struct AppSettings: Codable, Equatable {
    var hoverToOpen = true
    var hotKey: HotKeyPreset = .optionN
    var showToolDock = true
    var nudgesEnabled = true
    var nudgeSound = true
    var defaultFocusMinutes = 25
    var defaultTimerMode: TimerMode = .countdown
    var autoPauseOnSleep = true
    var remindersSyncEnabled = false
    var remindersListID: String?
    var mcpEnabled = false
    var mcpPort = 47823
    var mcpToken = Token.generate()
    var allowServerSpeechRecognition = false
    var copyClipsToClipboard = true
    var clipboardHistoryEnabled = true
    /// Raw `Tool` values shown as cards on the Workspace dashboard, in order.
    var dashboardTools = ["tasks", "focus", "notepad", "calendar"]
    var appleNotesSyncEnabled = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        hoverToOpen = try c.decodeIfPresent(Bool.self, forKey: .hoverToOpen) ?? d.hoverToOpen
        hotKey = (try? c.decodeIfPresent(HotKeyPreset.self, forKey: .hotKey)) ?? d.hotKey
        showToolDock = try c.decodeIfPresent(Bool.self, forKey: .showToolDock) ?? d.showToolDock
        nudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .nudgesEnabled) ?? d.nudgesEnabled
        nudgeSound = try c.decodeIfPresent(Bool.self, forKey: .nudgeSound) ?? d.nudgeSound
        defaultFocusMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultFocusMinutes) ?? d.defaultFocusMinutes
        defaultTimerMode = (try? c.decodeIfPresent(TimerMode.self, forKey: .defaultTimerMode)) ?? d.defaultTimerMode
        autoPauseOnSleep = try c.decodeIfPresent(Bool.self, forKey: .autoPauseOnSleep) ?? d.autoPauseOnSleep
        remindersSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersSyncEnabled) ?? d.remindersSyncEnabled
        remindersListID = try c.decodeIfPresent(String.self, forKey: .remindersListID)
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? d.mcpEnabled
        mcpPort = try c.decodeIfPresent(Int.self, forKey: .mcpPort) ?? d.mcpPort
        mcpToken = try c.decodeIfPresent(String.self, forKey: .mcpToken) ?? d.mcpToken
        allowServerSpeechRecognition = try c.decodeIfPresent(Bool.self, forKey: .allowServerSpeechRecognition) ?? d.allowServerSpeechRecognition
        copyClipsToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyClipsToClipboard) ?? d.copyClipsToClipboard
        clipboardHistoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? d.clipboardHistoryEnabled
        dashboardTools = try c.decodeIfPresent([String].self, forKey: .dashboardTools) ?? d.dashboardTools
        appleNotesSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .appleNotesSyncEnabled) ?? d.appleNotesSyncEnabled
    }
}

struct AppData: Codable {
    static let currentVersion = 1

    var version: Int = AppData.currentVersion
    var exportedAt: Date?
    var tasks: [TaskItem] = []
    var sessions: [FocusSession] = []
    var clips: [Clip] = []
    var notes: [String: String] = [:]
    var settings = AppSettings()
    var deletedReminderIDs: [String] = []
    /// Daily note key (`DayKey`) → linked Apple Notes note.
    var appleNoteLinks: [String: AppleNoteLink] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppData.currentVersion
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        deletedReminderIDs = try c.decodeIfPresent([String].self, forKey: .deletedReminderIDs) ?? []
        appleNoteLinks = try c.decodeIfPresent([String: AppleNoteLink].self, forKey: .appleNoteLinks) ?? [:]
    }
}

enum Token {
    static func generate(bytes: Int = 24) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        if SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer) != errSecSuccess {
            buffer = (0..<bytes).map { _ in UInt8.random(in: .min ... .max) }
        }
        return buffer.map { String(format: "%02x", $0) }.joined()
    }
}

/// What a daily note looked like on both sides the last time it was reconciled with Apple Notes.
struct AppleNoteLink: Codable, Hashable {
    var noteID: String
    var localText: String
    /// Normalized Notes text; nil until it's read back after Notchy last wrote the note.
    var remoteText: String?
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
    static func date(from key: String) -> Date? { formatter.date(from: key) }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
