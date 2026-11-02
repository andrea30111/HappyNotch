import Charts
import SwiftUI

struct InsightsView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case tasks = "Tasks"
        case focus = "Focus"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: Store
    @State private var metric: Metric = .tasks

    private var summary: InsightsSummary {
        InsightsSummary.compute(tasks: store.tasks, sessions: store.sessions)
    }

    var body: some View {
        let summary = self.summary
        HStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(symbol: "flame.fill", value: "\(summary.currentStreak)", unit: summary.currentStreak == 1 ? "day" : "days", label: "Current streak", tint: DS.Palette.voice)
                    StatTile(symbol: "trophy.fill", value: "\(summary.bestStreak)", unit: summary.bestStreak == 1 ? "day" : "days", label: "Best streak", tint: DS.Palette.notes)
                }
                HStack(spacing: 10) {
                    StatTile(symbol: "checkmark.circle.fill", value: "\(summary.completedThisWeek)", unit: "done", label: "This week", tint: DS.Palette.tasks)
                    StatTile(symbol: "bolt.fill", value: DateText.minutes(summary.focusMinutesThisWeek), unit: nil, label: "Focus this week", tint: DS.Palette.focus)
                }
            }
            .frame(width: 280)

            Card(tint: DS.Palette.insights) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CardTitle(title: "Last 14 days", symbol: "chart.bar.fill")
                        Spacer()
                        PillSegment(options: Metric.allCases.map { .init(value: $0, title: $0.rawValue) }, selection: $metric)
                    }
                    Chart(summary.days.suffix(14)) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value(metric == .tasks ? "Completed" : "Minutes", metric == .tasks ? Double(day.completed) : day.focusMinutes)
                        )
                        .foregroundStyle(DS.ink.opacity(Calendar.current.isDateInToday(day.date) ? 0.9 : 0.55))
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) {
                            AxisValueLabel(format: .dateTime.day().month(.narrow))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { AxisGridLine(); AxisValueLabel() }
                    }
                    .accessibilityLabel(metric == .tasks ? "Completed tasks per day" : "Focus minutes per day")
                    HStack {
                        Text("\(summary.totalCompleted) tasks completed")
                        Spacer()
                        Text("\(DateText.minutes(summary.totalFocusMinutes)) focused in total")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.inkSecondary)
                }
            }

            Card(tint: DS.Palette.events) {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(title: "Activity", symbol: "square.grid.3x3.fill")
                    ActivityHeatmap(days: summary.days)
                    Spacer(minLength: 0)
                    Text("Each square is a day. Darker means more done.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.inkSecondary)
                }
            }
            .frame(width: 230)
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let value: String
    let unit: String?
    let label: String
    let tint: Color

    var body: some View {
        Card(tint: tint, padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                    if let unit { Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(DS.inkSecondary) }
                }
                Text(label).font(.system(size: 11)).foregroundStyle(DS.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

private struct ActivityHeatmap: View {
    let days: [InsightsSummary.Day]

    private var weeks: [[InsightsSummary.Day]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var maxScore: Double {
        max(1, days.map(score).max() ?? 1)
    }

    private func score(_ day: InsightsSummary.Day) -> Double {
        Double(day.completed) + day.focusMinutes / 25
    }

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(weeks.indices, id: \.self) { index in
                VStack(spacing: 3) {
                    ForEach(weeks[index]) { day in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(DS.ink.opacity(day.isActive ? 0.18 + 0.72 * score(day) / maxScore : 0.07))
                            .frame(width: 10, height: 10)
                            .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.completed) done, \(Int(day.focusMinutes)) min focus")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity over the last \(weeks.count) weeks: active on \(days.filter(\.isActive).count) days")
    }
}
