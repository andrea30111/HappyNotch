import Combine
import EventKit
import Foundation

/// Opt-in two-way sync between Notchy tasks and one Apple Reminders list.
///
/// Each linked task stores the reminder identifier and the time it was last reconciled
/// (`syncedAt`). Whichever side changed after that point wins; if both changed, the most
/// recent edit wins.
@MainActor
final class RemindersSync: ObservableObject {
    struct ListInfo: Identifiable, Hashable {
        let id: String
        let title: String
    }

    @Published private(set) var authorization: EKAuthorizationStatus
    @Published private(set) var lists: [ListInfo] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published var lastError: String?

    private let store: Store
    private var pending: DispatchWorkItem?
    private var needsResync = false
    private var cancellables = Set<AnyCancellable>()
    private var ek: EKEventStore { EventStoreProvider.shared.store }

    init(store: Store) {
        self.store = store
        authorization = EKEventStore.authorizationStatus(for: .reminder)

        store.$tasks.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleSync(after: 0.8) }
            .store(in: &cancellables)

        if isAuthorized { loadLists() }
        if isEnabled { scheduleSync(after: 1) }
    }

    var isEnabled: Bool { store.settings.remindersSyncEnabled }
    var isAuthorized: Bool { authorization == .fullAccess }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            store.settings.remindersSyncEnabled = false
            pending?.cancel()
            return
        }
        Task {
            do {
                let granted = try await ek.requestFullAccessToReminders()
                authorization = EKEventStore.authorizationStatus(for: .reminder)
                guard granted else {
                    lastError = "Reminders access was denied. Allow it in System Settings › Privacy & Security › Reminders."
                    return
                }
                loadLists()
                if store.settings.remindersListID == nil {
                    store.settings.remindersListID = ek.defaultCalendarForNewReminders()?.calendarIdentifier
                }
                store.settings.remindersSyncEnabled = true
                lastError = nil
                await sync()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Asks for access without turning sync on.
    func requestAccess(completion: @escaping () -> Void) {
        Task {
            _ = try? await ek.requestFullAccessToReminders()
            authorization = EKEventStore.authorizationStatus(for: .reminder)
            if isAuthorized { loadLists() }
            completion()
        }
    }

    func selectList(_ id: String) {
        guard id != store.settings.remindersListID else { return }
        // Unlink everything first so switching lists can never look like remote deletions.
        store.tasks = store.tasks.map { task in
            var t = task
            t.reminderIdentifier = nil
            t.syncedAt = nil
            return t
        }
        store.deletedReminderIDs = []
        store.settings.remindersListID = id
        scheduleSync(after: 0.2)
    }

    func loadLists() {
        lists = ek.calendars(for: .reminder)
            .map { ListInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func scheduleSync(after delay: TimeInterval = 1.5) {
        guard isEnabled, isAuthorized else { return }
        if isSyncing {
            needsResync = true
            return
        }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.sync() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func sync() async {
        guard isEnabled, isAuthorized, !isSyncing else { return }
        guard let listID = store.settings.remindersListID, let list = ek.calendar(withIdentifier: listID) else {
            lastError = "Choose a Reminders list in Settings."
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if needsResync {
                needsResync = false
                scheduleSync()
            }
        }

        let remote = await fetchReminders(in: list)
        var remoteByID = Dictionary(remote.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var changedLocal = false
        var errors: [String] = []

        for rid in store.deletedReminderIDs {
            if let reminder = remoteByID[rid] ?? (ek.calendarItem(withIdentifier: rid) as? EKReminder) {
                do { try ek.remove(reminder, commit: true) } catch { errors.append(error.localizedDescription) }
            }
            remoteByID[rid] = nil
        }

        var result: [TaskItem] = []
        for var task in store.tasks {
            if let rid = task.reminderIdentifier {
                guard let reminder = remoteByID.removeValue(forKey: rid) ?? (ek.calendarItem(withIdentifier: rid) as? EKReminder) else {
                    changedLocal = true
                    continue
                }
                let synced = task.syncedAt ?? .distantPast
                let remoteModified = reminder.lastModifiedDate ?? .distantPast
                let localChanged = task.lastModified > synced
                let remoteChanged = remoteModified > synced.addingTimeInterval(1)

                if localChanged && (!remoteChanged || task.lastModified >= remoteModified) {
                    apply(task, to: reminder)
                    do {
                        try ek.save(reminder, commit: true)
                        task.syncedAt = Date()
                        changedLocal = true
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                } else if remoteChanged {
                    apply(reminder, to: &task)
                    task.lastModified = Date()
                    task.syncedAt = task.lastModified
                    changedLocal = true
                }
                result.append(task)
            } else if !task.isCompleted {
                let reminder = EKReminder(eventStore: ek)
                reminder.calendar = list
                apply(task, to: reminder)
                do {
                    try ek.save(reminder, commit: true)
                    task.reminderIdentifier = reminder.calendarItemIdentifier
                    task.syncedAt = Date()
                    changedLocal = true
                } catch {
                    errors.append(error.localizedDescription)
                }
                result.append(task)
            } else {
                result.append(task)
            }
        }

        var nextSort = (result.map(\.sortIndex).max() ?? 0) + 1
        for reminder in remoteByID.values where !reminder.isCompleted {
            var task = TaskItem(title: reminder.title ?? "Untitled")
            apply(reminder, to: &task)
            task.reminderIdentifier = reminder.calendarItemIdentifier
            task.syncedAt = Date()
            task.lastModified = task.syncedAt ?? Date()
            task.sortIndex = nextSort
            nextSort += 1
            result.append(task)
            changedLocal = true
        }

        if changedLocal { store.tasks = result }
        if !store.deletedReminderIDs.isEmpty { store.deletedReminderIDs = [] }
        lastError = errors.first
        lastSync = Date()
    }

    // MARK: Mapping

    private func fetchReminders(in list: EKCalendar) async -> [EKReminder] {
        let predicate = ek.predicateForReminders(in: [list])
        return await withCheckedContinuation { continuation in
            ek.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func apply(_ task: TaskItem, to reminder: EKReminder) {
        reminder.title = task.title
        reminder.notes = task.notes.isEmpty ? nil : task.notes
        reminder.priority = Self.ekPriority(task.priority)
        reminder.isCompleted = task.isCompleted
        if let due = task.dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if task.hasTime { components.formUnion([.hour, .minute]) }
            var dc = Calendar.current.dateComponents(components, from: due)
            if task.hasTime { dc.timeZone = .current }
            reminder.dueDateComponents = dc
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        if task.hasTime, let due = task.dueDate {
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
    }

    private func apply(_ reminder: EKReminder, to task: inout TaskItem) {
        let previousDue = task.dueDate
        task.title = reminder.title ?? task.title
        task.notes = reminder.notes ?? ""
        task.priority = Self.priority(from: reminder.priority)
        task.isCompleted = reminder.isCompleted
        task.completedAt = reminder.isCompleted ? (reminder.completionDate ?? task.completedAt ?? Date()) : nil
        if let dc = reminder.dueDateComponents, let date = Calendar.current.date(from: dc) {
            task.dueDate = date
            task.hasTime = dc.hour != nil
        } else {
            task.dueDate = nil
            task.hasTime = false
        }
        if task.dueDate != previousDue { task.reminderFired = false }
    }

    private static func ekPriority(_ priority: Priority) -> Int {
        switch priority {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    private static func priority(from value: Int) -> Priority {
        switch value {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }
}
