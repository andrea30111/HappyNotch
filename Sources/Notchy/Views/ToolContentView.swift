import SwiftUI

struct ToolContentView: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .workspace:
            WorkspaceDashboard()
        case .tasks:
            HStack(spacing: 10) {
                TasksCard()
                UpcomingTasksCard().frame(width: 300)
            }
        case .focus:
            HStack(spacing: 10) {
                TimerCard().frame(width: 260)
                FocusHistoryCard()
            }
        case .notepad:
            HStack(spacing: 10) {
                NotepadCard(showsDayNavigation: true)
                NotesHistoryCard().frame(width: 240)
            }
        case .calendar:
            EventsCard(expanded: true)
        case .week:
            WeekPlannerView()
        case .clips:
            ClipsView()
        case .clipboard:
            ClipboardView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        case .neurons:
            NeuronsView()
        case .call:
            CallView()
        }
    }
}

struct UpcomingTasksCard: View {
    @EnvironmentObject private var store: Store

    private var groups: [(day: Date, tasks: [TaskItem])] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let upcoming = store.tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return due >= cal.date(byAdding: .day, value: 1, to: start)! && due < cal.date(byAdding: .day, value: 15, to: start)!
        }
        return Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.dueDate!) }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, tasks: $0.value.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }) }
    }

    var body: some View {
        Card(tint: DS.Palette.tasks.opacity(0.85)) {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Upcoming", symbol: "calendar.badge.clock")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DateText.relativeDay(group.day).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DS.inkSecondary)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.tasks) { task in
                                    HStack(spacing: 6) {
                                        Button {
                                            store.toggleComplete(task.id)
                                        } label: {
                                            Image(systemName: "circle").font(.system(size: 13))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Complete \(task.title)")
                                        Text(task.title).font(.system(size: 12)).lineLimit(1)
                                        Spacer(minLength: 0)
                                        if task.hasTime, let due = task.dueDate {
                                            Text(due.formatted(date: .omitted, time: .shortened))
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(DS.inkSecondary)
                                        }
                                    }
                                    .contextMenu { TaskMenuItems(task: task) }
                                }
                            }
                        }
                        if groups.isEmpty {
                            Text("Nothing scheduled for the next two weeks.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
        }
    }
}

struct FocusHistoryCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var timer: FocusTimer

    private var todaySessions: [FocusSession] {
        store.sessions.filter { Calendar.current.isDateInToday($0.start) }.sorted { $0.start > $1.start }
    }

    var body: some View {
        Card(tint: DS.Palette.focus.opacity(0.85)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(title: "Today's focus", symbol: "bolt.fill")
                    Spacer()
                    Text(DateText.minutes(todaySessions.reduce(0) { $0 + $1.duration } / 60))
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 6) {
                    ForEach([15, 25, 50, 90], id: \.self) { minutes in
                        Button("\(minutes)m") { timer.start(taskID: timer.taskID, minutes: minutes, mode: .countdown) }
                            .buttonStyle(InkCapsuleButtonStyle())
                            .accessibilityLabel("Start a \(minutes) minute focus session")
                    }
                    Button {
                        timer.start(taskID: timer.taskID, mode: .stopwatch)
                    } label: {
                        Label("Stopwatch", systemImage: "stopwatch")
                    }
                    .buttonStyle(InkCapsuleButtonStyle())
                }
                .disabled(timer.isActive)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(todaySessions) { session in
                            HStack {
                                Text(session.start.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(DS.inkSecondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(session.taskTitle ?? "Focus session").font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(DateText.minutes(session.duration / 60)).font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                        if todaySessions.isEmpty {
                            Text("No sessions yet today. Pick a length above or press ⌘T.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }
}
