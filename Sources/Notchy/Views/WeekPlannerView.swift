import SwiftUI

/// Weekly board: drag tasks between days (or to "Someday" to clear the date).
struct WeekPlannerView: View {
    @EnvironmentObject private var store: Store
    @State private var weekStart = Calendar.current.startOfWeek(for: Date())

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    WeekDayColumn(day: day, weekDays: days, tasks: tasks(on: day))
                }
                WeekDayColumn(day: nil, weekDays: days, tasks: somedayTasks)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Week planner")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(weekTitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            HeaderIconButton(symbol: "chevron.left", label: "Previous week") { shift(-1) }
            Button("This week") {
                withAnimation(DS.snappy) { weekStart = Calendar.current.startOfWeek(for: Date()) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            HeaderIconButton(symbol: "chevron.right", label: "Next week") { shift(1) }
        }
        .foregroundStyle(.white)
    }

    private var weekTitle: String {
        guard let end = days.last else { return "" }
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func tasks(on day: Date) -> [TaskItem] {
        let cal = Calendar.current
        return store.tasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: day)
            }
            .sorted { ($0.isCompleted ? 1 : 0, $0.sortIndex) < ($1.isCompleted ? 1 : 0, $1.sortIndex) }
    }

    private var somedayTasks: [TaskItem] {
        store.tasks.filter { $0.dueDate == nil && !$0.isCompleted }.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func shift(_ weeks: Int) {
        withAnimation(DS.snappy) {
            weekStart = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
        }
    }
}

private struct WeekDayColumn: View {
    let day: Date?
    let weekDays: [Date]
    let tasks: [TaskItem]

    @EnvironmentObject private var store: Store
    @State private var isTargeted = false
    @State private var draft = ""

    private var isToday: Bool { day.map(Calendar.current.isDateInToday) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(day.map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "Someday")
                    .font(.system(size: 11, weight: .bold))
                if let day {
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isToday ? Color.white : DS.inkSecondary)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(isToday ? DS.ink : .clear))
                }
                Spacer(minLength: 0)
                if !tasks.isEmpty {
                    Text("\(tasks.filter { !$0.isCompleted }.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(tasks) { task in
                        WeekTaskChip(task: task, weekDays: weekDays)
                            .draggable(task.id.uuidString) {
                                Text(task.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.Palette.week))
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            TextField("+ Add", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.06)))
                .onSubmit {
                    store.addTask(text: draft, defaultDay: day)
                    draft = ""
                }
                .accessibilityLabel("Add task to \(day.map { $0.formatted(.dateTime.weekday(.wide)) } ?? "Someday")")
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Palette.week.opacity(day == nil ? 0.6 : (isToday ? 1 : 0.8)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isTargeted ? 0.95 : 0), lineWidth: 2)
        }
        .foregroundStyle(DS.ink)
        .environment(\.colorScheme, .light)
        .dropDestination(for: String.self) { ids, _ in
            let uuids = ids.compactMap(UUID.init(uuidString:))
            guard !uuids.isEmpty else { return false }
            withAnimation(DS.snappy) {
                for id in uuids { store.reschedule(id, to: day) }
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(DS.snappy, value: isTargeted)
    }
}

private struct WeekTaskChip: View {
    let task: TaskItem
    let weekDays: [Date]
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Button {
                store.toggleComplete(task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) as not done" : "Complete \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .strikethrough(task.isCompleted)
                    .lineLimit(3)
                if task.hasTime, let due = task.dueDate {
                    Text(due.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(DS.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(task.isCompleted ? 0.2 : 0.45)))
        .opacity(task.isCompleted ? 0.6 : 1)
        .contextMenu {
            Menu("Move To") {
                ForEach(weekDays, id: \.self) { day in
                    Button(day.formatted(.dateTime.weekday(.wide).day())) { store.reschedule(task.id, to: day) }
                }
                Divider()
                Button("Someday") { store.reschedule(task.id, to: nil) }
            }
            Button("Delete", role: .destructive) { store.deleteTask(task.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            ForEach(weekDays, id: \.self) { day in
                Button("Move to \(day.formatted(.dateTime.weekday(.wide)))") { store.reschedule(task.id, to: day) }
            }
            Button("Move to Someday") { store.reschedule(task.id, to: nil) }
        }
    }
}
