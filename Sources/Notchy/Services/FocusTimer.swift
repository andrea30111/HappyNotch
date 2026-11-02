import AppKit
import Combine

/// Ticking values live in their own object so only the views that show the clock redraw every second.
@MainActor
final class FocusClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var remaining: TimeInterval = 0
    @Published var progress: Double = 0
    @Published var display: String = "25:00"
}

@MainActor
final class FocusTimer: ObservableObject {
    enum Phase: Equatable { case idle, running, paused, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mode: TimerMode
    @Published private(set) var taskID: UUID?
    @Published private(set) var duration: TimeInterval
    @Published private(set) var pausedBySleep = false

    let clock = FocusClock()
    var onFinish: ((FocusTimer) -> Void)?
    var onSleepPause: (() -> Void)?

    private let store: Store
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    private var sessionStart: Date?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    init(store: Store) {
        self.store = store
        mode = store.settings.defaultTimerMode
        duration = TimeInterval(store.settings.defaultFocusMinutes * 60)
        tick()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
    }

    var isActive: Bool { phase == .running || phase == .paused }
    var elapsed: TimeInterval { accumulated + (runningSince.map { Date().timeIntervalSince($0) } ?? 0) }
    var remaining: TimeInterval { max(0, duration - elapsed) }
    var task: TaskItem? { taskID.flatMap { store.task($0) } }

    // MARK: Controls

    func start(taskID: UUID? = nil, minutes: Int? = nil, mode: TimerMode? = nil) {
        commitSession()
        self.taskID = taskID
        if let mode { self.mode = mode }
        if let minutes { duration = TimeInterval(minutes * 60) }
        accumulated = 0
        runningSince = Date()
        sessionStart = Date()
        pausedBySleep = false
        phase = .running
        startTicker()
        tick()
    }

    func pause() {
        guard phase == .running else { return }
        accumulated = elapsed
        runningSince = nil
        phase = .paused
        stopTicker()
        tick()
    }

    func resume() {
        guard phase == .paused else { return }
        runningSince = Date()
        pausedBySleep = false
        phase = .running
        startTicker()
        tick()
    }

    func toggle() {
        switch phase {
        case .running: pause()
        case .paused: resume()
        case .idle, .finished: start(taskID: taskID)
        }
    }

    func addFiveMinutes() {
        if phase == .finished {
            start(taskID: taskID, minutes: 5, mode: .countdown)
            return
        }
        duration += 5 * 60
        tick()
    }

    /// Ends the session and keeps the focused time. Optionally marks the linked task as done.
    func finish(markTaskComplete: Bool = false) {
        commitSession()
        if markTaskComplete, let taskID { store.setCompleted(taskID, true) }
        reset()
    }

    func discard() {
        sessionStart = nil
        reset()
    }

    func setDuration(minutes: Int) {
        duration = TimeInterval(max(1, minutes) * 60)
        if mode == .stopwatch { mode = .countdown }
        tick()
    }

    func setMode(_ newMode: TimerMode) {
        guard newMode != mode else { return }
        mode = newMode
        tick()
    }

    func select(taskID: UUID?) {
        self.taskID = taskID
    }

    private func reset() {
        stopTicker()
        accumulated = 0
        runningSince = nil
        sessionStart = nil
        pausedBySleep = false
        phase = .idle
        duration = TimeInterval(store.settings.defaultFocusMinutes * 60)
        mode = store.settings.defaultTimerMode
        tick()
    }

    // MARK: Ticking

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let elapsed = self.elapsed
        if mode == .countdown, phase == .running, elapsed >= duration {
            accumulated = duration
            runningSince = nil
            stopTicker()
            commitSession()
            phase = .finished
            publish(elapsed: duration)
            onFinish?(self)
            return
        }
        publish(elapsed: elapsed)
    }

    private func publish(elapsed: TimeInterval) {
        let remaining = max(0, duration - elapsed)
        clock.elapsed = elapsed
        clock.remaining = remaining
        switch mode {
        case .countdown:
            clock.progress = duration > 0 ? min(1, elapsed / duration) : 0
            clock.display = Self.format(phase == .idle ? duration : remaining)
        case .stopwatch:
            clock.progress = elapsed.truncatingRemainder(dividingBy: 3600) / 3600
            clock.display = Self.format(elapsed)
        }
    }

    private func commitSession() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        store.recordFocus(taskID: taskID, start: start, duration: min(elapsed, mode == .countdown ? duration : .infinity))
    }

    // MARK: Sleep

    private func handleSleep() {
        guard phase == .running, store.settings.autoPauseOnSleep else { return }
        pause()
        pausedBySleep = true
    }

    private func handleWake() {
        if pausedBySleep { onSleepPause?() }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
