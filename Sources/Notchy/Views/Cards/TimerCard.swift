import SwiftUI

struct TimerCard: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var store: Store

    private var openTasks: [TaskItem] { store.tasks(on: Date(), completed: false) }

    var body: some View {
        Card(tint: DS.Palette.focus) {
            VStack(spacing: 10) {
                taskPicker
                Spacer(minLength: 0)
                TimerReadout(clock: timer.clock, phase: timer.phase, mode: timer.mode)
                Spacer(minLength: 0)
                controls
                footer
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var taskPicker: some View {
        Menu {
            Button("No task") { timer.select(taskID: nil) }
            if !openTasks.isEmpty { Divider() }
            ForEach(openTasks.prefix(12)) { task in
                Button(task.title) { timer.select(taskID: task.id) }
            }
        } label: {
            Text(timer.task?.title ?? "Focus")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(timer.isActive ? .hidden : .visible)
        .disabled(timer.isActive)
        .help("Choose the task to focus on")
        .accessibilityLabel("Focus task: \(timer.task?.title ?? "none")")
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                timer.toggle()
            } label: {
                Label(primaryTitle, systemImage: primarySymbol)
                    .frame(minWidth: 64)
            }
            .buttonStyle(InkCapsuleButtonStyle())
            .accessibilityHint("Shortcut Command T")

            if timer.mode == .countdown && (timer.isActive || timer.phase == .finished) {
                Button("+5") { timer.addFiveMinutes() }
                    .buttonStyle(InkCapsuleButtonStyle())
                    .accessibilityLabel("Add five minutes")
            }

            if timer.isActive {
                Button {
                    timer.finish(markTaskComplete: timer.taskID != nil)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.42)))
                }
                .buttonStyle(.plain)
                .help(timer.taskID != nil ? "Finish and complete the task" : "Finish session")
                .accessibilityLabel(timer.taskID != nil ? "Finish and complete the task" : "Finish session")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach([5, 15, 25, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) min") { timer.setDuration(minutes: minutes) }
                }
            } label: {
                Label("Set time", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(timer.phase == .running)

            Menu {
                Picker("Mode", selection: Binding(get: { timer.mode }, set: { timer.setMode($0) })) {
                    ForEach(TimerMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                if timer.isActive {
                    Divider()
                    Button("Stop and Log Session") { timer.finish() }
                    Button("Discard Session", role: .destructive) { timer.discard() }
                }
                Divider()
                DashboardMenuItems(tool: .focus)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Timer options")
        }
        .foregroundStyle(DS.inkSecondary)
    }

    private var primaryTitle: String {
        switch timer.phase {
        case .running: return "Pause"
        case .paused: return "Resume"
        case .idle: return "Start"
        case .finished: return "Again"
        }
    }

    private var primarySymbol: String {
        switch timer.phase {
        case .running: return "pause.fill"
        case .paused, .idle: return "play.fill"
        case .finished: return "arrow.clockwise"
        }
    }
}

/// Observes the per-second clock so only this subtree redraws while the timer runs.
struct TimerReadout: View {
    @ObservedObject var clock: FocusClock
    let phase: FocusTimer.Phase
    let mode: TimerMode

    private var caption: String {
        switch phase {
        case .idle: return mode == .countdown ? "Ready" : "Stopwatch"
        case .running: return mode == .countdown ? "Remaining" : "Elapsed"
        case .paused: return "Paused"
        case .finished: return "Done"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            let long = clock.display.count > 5
            ViewThatFits(in: .horizontal) {
                DotMatrixText(text: clock.display, dot: long ? 2.3 : 3.4, spacing: long ? 1.1 : 1.6)
                DotMatrixText(text: clock.display, dot: long ? 1.9 : 2.7, spacing: long ? 0.9 : 1.3)
                DotMatrixText(text: clock.display, dot: long ? 1.5 : 2.1, spacing: long ? 0.7 : 1.0)
            }
            .opacity(phase == .paused ? 0.55 : 1)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.inkSecondary)
            if mode == .countdown {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.1))
                        Capsule().fill(DS.ink).frame(width: proxy.size.width * clock.progress)
                    }
                }
                .frame(width: 84, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(clock.display)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
