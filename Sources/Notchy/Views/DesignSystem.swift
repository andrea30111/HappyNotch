import SwiftUI

enum DS {
    enum Palette {
        static let tasks = Color(red: 0.639, green: 0.757, blue: 0.616)
        static let focus = Color(red: 0.690, green: 0.651, blue: 0.859)
        static let notes = Color(red: 0.890, green: 0.835, blue: 0.494)
        static let events = Color(red: 0.639, green: 0.737, blue: 0.871)
        static let week = Color(red: 0.910, green: 0.710, blue: 0.588)
        static let clips = Color(red: 0.886, green: 0.659, blue: 0.749)
        static let clipboard = Color(red: 0.851, green: 0.792, blue: 0.698)
        static let insights = Color(red: 0.545, green: 0.796, blue: 0.784)
        static let settings = Color(red: 0.760, green: 0.760, blue: 0.780)
        static let voice = Color(red: 0.980, green: 0.580, blue: 0.470)
        static let workspace = Color(red: 0.960, green: 0.960, blue: 0.960)
    }

    static let ink = Color.black.opacity(0.82)
    static let inkSecondary = Color.black.opacity(0.55)
    static let inkTertiary = Color.black.opacity(0.34)
    static let hairline = Color.black.opacity(0.08)
    static let wash = Color.white.opacity(0.38)
    static let danger = Color(red: 0.70, green: 0.14, blue: 0.12)

    static let cardRadius: CGFloat = 20
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.9)
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case workspace, tasks, focus, notepad, calendar, week, clips, clipboard, insights, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .tasks: return "Tasks"
        case .focus: return "Focus"
        case .notepad: return "Notepad"
        case .calendar: return "Calendar"
        case .week: return "Week"
        case .clips: return "Clips"
        case .clipboard: return "Clipboard"
        case .insights: return "Insights"
        case .settings: return "Customize"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "square.grid.2x2.fill"
        case .tasks: return "checklist"
        case .focus: return "timer"
        case .notepad: return "note.text"
        case .calendar: return "calendar"
        case .week: return "rectangle.split.3x1.fill"
        case .clips: return "camera.viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .insights: return "chart.bar.fill"
        case .settings: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .workspace: return DS.Palette.workspace
        case .tasks: return DS.Palette.tasks
        case .focus: return DS.Palette.focus
        case .notepad: return DS.Palette.notes
        case .calendar: return DS.Palette.events
        case .week: return DS.Palette.week
        case .clips: return DS.Palette.clips
        case .clipboard: return DS.Palette.clipboard
        case .insights: return DS.Palette.insights
        case .settings: return DS.Palette.settings
        }
    }

    var shortcut: String {
        let index = (Tool.allCases.firstIndex(of: self) ?? 0) + 1
        return "⌘\(index % 10)"
    }
}

/// Pastel card with dark ink, a drag-handle pill on top and light-mode controls inside.
struct Card<Content: View>: View {
    var tint: Color
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, padding)
            .padding(.top, padding + 4)
            .padding(.bottom, padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 26, height: 4)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.ink)
            .environment(\.colorScheme, .light)
    }
}

struct CardTitle: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small round icon button used inside cards.
struct InkIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 22
    var weight: Font.Weight = .semibold
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: weight))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct InkCapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(prominent ? Color.black.opacity(0.78) : Color.white.opacity(0.42)))
            .foregroundStyle(prominent ? Color.white : DS.ink)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.snappy, value: configuration.isPressed)
    }
}

/// Pill-shaped segmented control ("To do 6 | Completed 1").
struct PillSegment<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var count: Int?
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(DS.snappy) { selection = option.value }
                } label: {
                    HStack(spacing: 5) {
                        Text(option.title)
                        if let count = option.count {
                            Text("\(count)").foregroundStyle(DS.inkSecondary)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(selected ? Color.white.opacity(0.6) : Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct IsNotchPanelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the notch panel, false in the dashboard window.
    var isNotchPanel: Bool {
        get { self[IsNotchPanelKey.self] }
        set { self[IsNotchPanelKey.self] = newValue }
    }
}

enum DateText {
    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if (2..<7).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func due(_ date: Date, hasTime: Bool) -> String {
        let day = relativeDay(date)
        return hasTime ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    }

    static func minutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m) min"
    }
}
