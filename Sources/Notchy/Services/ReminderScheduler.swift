import AppKit
import Combine

/// Fires a notch nudge when a timed task becomes due. Keeps a single timer armed for the
/// next due date instead of polling.
@MainActor
final class ReminderScheduler {
    private let store: Store
    private let state: AppState
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(store: Store, state: AppState) {
        self.store = store
        self.state = state
        store.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        let now = Date()

        let due = store.tasks.filter { task in
            guard !task.isCompleted, !task.reminderFired, let date = task.reminderDate else { return false }
            return date <= now
        }
        if !due.isEmpty {
            let fresh = due.filter { now.timeIntervalSince($0.reminderDate ?? now) < 6 * 3600 }
                .sorted { ($0.reminderDate ?? now) < ($1.reminderDate ?? now) }
            if let first = fresh.first {
                let extra = fresh.count > 1 ? " +\(fresh.count - 1) more" : ""
                state.post(Nudge(symbol: "bell.fill", title: "Due now", subtitle: first.title + extra, tint: DS.Palette.tasks, sound: "Tink"))
            }
            let ids = Set(due.map(\.id))
            store.tasks = store.tasks.map { task in
                guard ids.contains(task.id) else { return task }
                var t = task
                t.reminderFired = true
                return t
            }
            return
        }

        let next = store.tasks
            .compactMap { !$0.isCompleted && !$0.reminderFired ? $0.reminderDate : nil }
            .filter { $0 > now }
            .min()
        guard let next else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
