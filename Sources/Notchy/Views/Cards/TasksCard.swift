import SwiftUI

struct TasksCard: View {
    @EnvironmentObject private var store: Store

    @State private var showCompleted = false
    @State private var editingID: UUID?
    /// Heights of the two row stacks, used to shrink the upper list when Today needs the room.
    @State private var contentHeights: [String: CGFloat] = [:]

    private var allTasks: [TaskItem] {
        store.tasks
            .filter { $0.isCompleted == showCompleted }
            .sorted { lhs, rhs in
                if showCompleted { return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast) }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    private var todayTasks: [TaskItem] { store.tasks(on: Date(), completed: showCompleted) }

    var body: some View {
        Card(tint: DS.Palette.tasks) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    CardTitle(title: "Tasks")
                    Spacer(minLength: 4)
                    PillSegment(options: [
                        .init(value: false, title: "To do", count: store.tasks.filter { !$0.isCompleted }.count),
                        .init(value: true, title: "Completed", count: store.tasks.filter(\.isCompleted).count),
                    ], selection: $showCompleted)
                }
                GeometryReader { geo in
                    let split = splitHeights(total: geo.size.height)
                    VStack(alignment: .leading, spacing: 8) {
                        taskSection("All", id: "all", items: allTasks, empty: showCompleted ? "Nothing completed yet" : "No tasks yet.", height: split.all)
                        taskSection("Today", id: "today", items: todayTasks, empty: showCompleted ? "Nothing completed today" : "Nothing due today.", height: split.today)
                    }
                }
                .frame(maxHeight: .infinity)
                .onPreferenceChange(TaskSectionHeightKey.self) { heights in
                    if heights != contentHeights { contentHeights = heights }
                }
                HStack(spacing: 8) {
                    QuickAddField()
                    Text("Drag to reorder")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.inkTertiary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay {
            if let id = editingID, let task = store.task(id) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .onTapGesture { editingID = nil }
                    TaskEditor(task: task) { editingID = nil }
                        .padding(14)
                }
                .transition(.opacity)
            }
        }
        .animation(DS.snappy, value: editingID)
    }

    /// Each list gets half the space. When Today has more rows than fit in that half and All
    /// does not, All shrinks to its content and Today takes the rest.
    private func splitHeights(total: CGFloat) -> (all: CGFloat, today: CGFloat) {
        let gap: CGFloat = 8
        let usable = max(0, total - gap)
        let half = usable / 2
        let label: CGFloat = 18
        let allBlock = (contentHeights["all"] ?? 0) + label
        let todayBlock = (contentHeights["today"] ?? 0) + label
        guard todayBlock > half, allBlock > 0, allBlock < half else { return (half, usable - half) }
        let allHeight = min(allBlock, half)
        return (allHeight, usable - allHeight)
    }

    private func taskSection(_ title: String, id: String, items: [TaskItem], empty: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { task in
                        TaskRow(task: task) { editingID = task.id }
                            .draggable(task.id.uuidString) {
                                Text(task.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.Palette.tasks))
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                guard let raw = ids.first, let source = UUID(uuidString: raw), source != task.id else { return false }
                                withAnimation(DS.snappy) { store.moveTask(source, before: task.id) }
                                return true
                            }
                    }
                    if items.isEmpty {
                        Text(empty)
                            .font(.system(size: 12))
                            .foregroundStyle(DS.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    GeometryReader { proxy in
                        Color.clear.preference(key: TaskSectionHeightKey.self, value: [id: proxy.size.height])
                    }
                }
            }
        }
        .frame(height: height, alignment: .top)
    }
}

private struct TaskSectionHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TaskRow: View {
    let task: TaskItem
    var onEdit: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    private var isFocusing: Bool { timer.taskID == task.id && timer.isActive }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(DS.spring) { store.toggleComplete(task.id) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.isCompleted ? DS.ink : DS.inkSecondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) as not done" : "Complete \(task.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isCompleted, color: DS.inkSecondary)
                    .foregroundStyle(task.isCompleted ? DS.inkSecondary : DS.ink)
                    .lineLimit(2)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering || isFocusing {
                HStack(spacing: 0) {
                    InkIconButton(symbol: isFocusing && timer.phase == .running ? "pause.fill" : "play.fill", label: isFocusing ? "Pause focus" : "Start focus") {
                        if isFocusing {
                            timer.toggle()
                        } else {
                            timer.start(taskID: task.id)
                        }
                    }
                    InkIconButton(symbol: "square.and.pencil", label: "Edit task", action: onEdit)
                    Menu {
                        TaskMenuItems(task: task)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More actions")
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(DS.snappy, value: hovering)
        .contextMenu { TaskMenuItems(task: task) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Start focus") { timer.start(taskID: task.id) }
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: "Delete") { store.deleteTask(task.id) }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if isFocusing {
                Label("Focusing now", systemImage: "bolt.fill")
            } else if task.focusedSeconds >= 60 {
                Label("Focused · \(DateText.minutes(task.focusedSeconds / 60))", systemImage: "timer")
            }
            if let due = task.dueDate {
                if task.isOverdue() {
                    Label("Overdue · \(DateText.due(due, hasTime: task.hasTime))", systemImage: "exclamationmark.circle")
                        .foregroundStyle(DS.danger)
                } else if task.hasTime {
                    Label(Calendar.current.isDateInToday(due) ? due.formatted(date: .omitted, time: .shortened) : DateText.due(due, hasTime: true), systemImage: "bell")
                } else if !Calendar.current.isDateInToday(due) {
                    Label(DateText.relativeDay(due), systemImage: "calendar")
                }
            }
            if task.priority >= .medium {
                Label(task.priority.label, systemImage: "flag.fill")
            }
            if task.reminderIdentifier != nil {
                Image(systemName: "icloud")
                    .accessibilityLabel("Synced with Reminders")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(DS.inkSecondary)
        .labelStyle(CompactLabelStyle())
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9.5, weight: .semibold))
            configuration.title
        }
    }
}

/// Shared by the row's "…" menu and its context menu.
struct TaskMenuItems: View {
    let task: TaskItem
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var timer: FocusTimer

    var body: some View {
        let cal = Calendar.current
        Button("Start Focus") { timer.start(taskID: task.id) }
        Button(task.isCompleted ? "Mark as Not Done" : "Mark as Done") { store.toggleComplete(task.id) }
        Divider()
        Menu("Move To") {
            Button("Today") { store.reschedule(task.id, to: Date()) }
            Button("Tomorrow") { store.reschedule(task.id, to: cal.date(byAdding: .day, value: 1, to: Date())) }
            Button("Next Week") {
                store.reschedule(task.id, to: cal.date(byAdding: .weekOfYear, value: 1, to: cal.startOfWeek(for: Date())))
            }
            Divider()
            Button("No Date") { store.reschedule(task.id, to: nil) }
        }
        Menu("Priority") {
            ForEach(Priority.allCases.reversed()) { priority in
                Button {
                    store.updateTask(task.id) { $0.priority = priority }
                } label: {
                    if task.priority == priority {
                        Label(priority.label, systemImage: "checkmark")
                    } else {
                        Text(priority.label)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.deleteTask(task.id) }
    }
}

/// Inline editor shown over the card (popovers would steal key focus from the panel and close it).
struct TaskEditor: View {
    let onDone: () -> Void
    @EnvironmentObject private var store: Store
    @State private var draft: TaskItem

    init(task: TaskItem, onDone: @escaping () -> Void) {
        _draft = State(initialValue: task)
        self.onDone = onDone
    }

    private var hasDue: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { on in
                draft.dueDate = on ? Calendar.current.startOfDay(for: Date()) : nil
                if !on { draft.hasTime = false }
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Title")
            HStack(spacing: 10) {
                Toggle("Due", isOn: hasDue)
                if draft.dueDate != nil {
                    DatePicker("Due date", selection: dueBinding, displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                        .datePickerStyle(.field)
                        .labelsHidden()
                    Toggle("Time", isOn: $draft.hasTime)
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            Picker("Priority", selection: $draft.priority) {
                ForEach(Priority.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11))
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
            HStack {
                Button("Delete", role: .destructive) {
                    store.deleteTask(draft.id)
                    onDone()
                }
                .foregroundStyle(DS.danger)
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let edited = draft
                    store.updateTask(edited.id) { task in
                        task.title = edited.title.trimmingCharacters(in: .whitespaces).isEmpty ? task.title : edited.title
                        task.notes = edited.notes
                        task.priority = edited.priority
                        task.dueDate = edited.dueDate
                        task.hasTime = edited.dueDate != nil && edited.hasTime
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.97)))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit task")
    }
}
