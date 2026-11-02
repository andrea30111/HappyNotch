import Foundation

struct InsightsSummary {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let completed: Int
        let focusMinutes: Double
        var isActive: Bool { completed > 0 || focusMinutes >= 1 }
    }

    let days: [Day]
    let currentStreak: Int
    let bestStreak: Int
    let completedToday: Int
    let completedThisWeek: Int
    let focusMinutesToday: Double
    let focusMinutesThisWeek: Double
    let totalCompleted: Int
    let totalFocusMinutes: Double

    /// A day counts towards a streak when at least one task was completed or a minute of focus was logged.
    static func compute(
        tasks: [TaskItem],
        sessions: [FocusSession],
        now: Date = Date(),
        calendar: Calendar = .current,
        window: Int = 112
    ) -> InsightsSummary {
        var completedByDay: [Date: Int] = [:]
        for task in tasks where task.isCompleted {
            guard let done = task.completedAt else { continue }
            completedByDay[calendar.startOfDay(for: done), default: 0] += 1
        }
        var focusByDay: [Date: Double] = [:]
        for session in sessions {
            focusByDay[calendar.startOfDay(for: session.start), default: 0] += session.duration / 60
        }

        let today = calendar.startOfDay(for: now)
        let days: [Day] = (0..<window).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, completed: completedByDay[date] ?? 0, focusMinutes: focusByDay[date] ?? 0)
        }

        let activeDays = Set(completedByDay.filter { $0.value > 0 }.keys)
            .union(focusByDay.filter { $0.value >= 1 }.keys)

        var current = 0
        var cursor = activeDays.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var best = 0
        var run = 0
        var previous: Date?
        for day in activeDays.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }

        let weekStart = calendar.startOfWeek(for: now)
        let thisWeek = completedByDay.filter { $0.key >= weekStart }.values.reduce(0, +)
        let focusWeek = focusByDay.filter { $0.key >= weekStart }.values.reduce(0, +)

        return InsightsSummary(
            days: days,
            currentStreak: current,
            bestStreak: max(best, current),
            completedToday: completedByDay[today] ?? 0,
            completedThisWeek: thisWeek,
            focusMinutesToday: focusByDay[today] ?? 0,
            focusMinutesThisWeek: focusWeek,
            totalCompleted: completedByDay.values.reduce(0, +),
            totalFocusMinutes: focusByDay.values.reduce(0, +)
        )
    }
}
