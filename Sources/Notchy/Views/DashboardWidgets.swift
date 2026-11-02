import Charts
import SwiftUI

extension Tool {
    /// Tools that can be shown as a card on the Workspace dashboard.
    static var dashboardCandidates: [Tool] { allCases.filter(\.canBeOnDashboard) }
    var canBeOnDashboard: Bool { self != .workspace && self != .settings && self != .neurons }
}

extension Store {
    var dashboardTools: [Tool] {
        settings.dashboardTools.compactMap(Tool.init(rawValue:)).filter(\.canBeOnDashboard)
    }

    func isOnDashboard(_ tool: Tool) -> Bool { settings.dashboardTools.contains(tool.rawValue) }

    /// Whether `tool` can be added without squeezing cards below their minimum width.
    func dashboardHasRoom(for tool: Tool) -> Bool {
        isOnDashboard(tool) || DashboardLayout.fits(dashboardTools + [tool])
    }

    /// Adds or removes `tool`. Returns false when adding was refused because the dashboard is full.
    @discardableResult
    func toggleDashboard(_ tool: Tool) -> Bool {
        guard tool.canBeOnDashboard else { return false }
        if isOnDashboard(tool) {
            settings.dashboardTools.removeAll { $0 == tool.rawValue }
            return true
        }
        guard dashboardHasRoom(for: tool) else { return false }
        settings.dashboardTools.append(tool.rawValue)
        return true
    }

    func moveOnDashboard(_ tool: Tool, by offset: Int) {
        var list = settings.dashboardTools
        guard let index = list.firstIndex(of: tool.rawValue) else { return }
        let target = min(max(index + offset, 0), list.count - 1)
        guard target != index else { return }
        list.swapAt(index, target)
        settings.dashboardTools = list
    }
}

/// "Add to Dashboard" / "Remove from Dashboard" items for a tool's ••• menu.
struct DashboardMenuItems: View {
    let tool: Tool
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState

    var body: some View {
        if tool.canBeOnDashboard {
            if store.isOnDashboard(tool) {
                Button {
                    store.toggleDashboard(tool)
                } label: {
                    Label("Remove from Dashboard", systemImage: "rectangle.badge.minus")
                }
                if store.dashboardTools.count > 1 {
                    Button("Move Left on Dashboard") { store.moveOnDashboard(tool, by: -1) }
                        .disabled(store.dashboardTools.first == tool)
                    Button("Move Right on Dashboard") { store.moveOnDashboard(tool, by: 1) }
                        .disabled(store.dashboardTools.last == tool)
                }
            } else {
                Button {
                    if store.toggleDashboard(tool) {
                        state.post(Nudge(symbol: "rectangle.badge.plus", title: "Added to Dashboard", subtitle: tool.title, tint: tool.tint, duration: 2))
                    } else {
                        state.post(Nudge(symbol: "rectangle.badge.exclamationmark", title: "Dashboard is full", subtitle: "Drag a card out of the notch to make room.", tint: tool.tint, duration: 3.5))
                    }
                } label: {
                    Label(store.dashboardHasRoom(for: tool) ? "Add to Dashboard" : "Add to Dashboard (Full)", systemImage: "rectangle.badge.plus")
                }
            }
        }
    }
}

/// The ••• menu shown in the panel header for the open tool.
struct ToolOptionsMenu: View {
    let tool: Tool
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        Menu {
            if tool == .workspace {
                Section("Show on Dashboard") {
                    ForEach(Tool.dashboardCandidates) { candidate in
                        Toggle(isOn: Binding(get: { store.isOnDashboard(candidate) }, set: { _ in store.toggleDashboard(candidate) })) {
                            Label(candidate.title, systemImage: candidate.symbol)
                        }
                        .disabled(!store.dashboardHasRoom(for: candidate))
                    }
                }
                Divider()
                Button("Reset Dashboard") { store.settings.dashboardTools = AppSettings().dashboardTools }
            } else {
                DashboardMenuItems(tool: tool)
            }
            Divider()
            Button("Open in Window") { state.openDashboard(tool) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("\(tool.title) options")
        .accessibilityLabel("\(tool.title) options")
    }
}

// MARK: - Workspace

/// Card widths for the dashboard row. Cards shrink toward their minimum to fit the panel;
/// a tool can only be added while every card still fits at its minimum width.
enum DashboardLayout {
    static let spacing: CGFloat = 10
    /// Width available inside the notch panel (panel width minus its horizontal padding).
    static var panelContentWidth: CGFloat { NotchLayout.panelWidth - 2 * (8 + 14) }

    static func preferredWidth(_ tool: Tool) -> CGFloat {
        switch tool {
        case .tasks: return 300
        case .focus: return 170
        case .notepad: return 172
        case .calendar: return 180
        default: return 190
        }
    }

    static func minimumWidth(_ tool: Tool) -> CGFloat {
        switch tool {
        case .tasks: return 220
        case .focus, .notepad: return 140
        default: return 150
        }
    }

    static func fits(_ tools: [Tool], in width: CGFloat = panelContentWidth) -> Bool {
        tools.reduce(0) { $0 + minimumWidth($1) } + spacing * CGFloat(max(0, tools.count - 1)) <= width
    }

    static func widths(for tools: [Tool], in width: CGFloat) -> [CGFloat] {
        let available = width - spacing * CGFloat(max(0, tools.count - 1))
        let preferred = tools.map(preferredWidth)
        let total = preferred.reduce(0, +)
        guard total > 0 else { return [] }
        if total <= available {
            if let tasks = tools.firstIndex(of: .tasks) {
                var result = preferred
                result[tasks] += available - total
                return result
            }
            return preferred.map { $0 * available / total }
        }
        let minimums = tools.map(minimumWidth)
        let slack = zip(preferred, minimums).reduce(0) { $0 + $1.0 - $1.1 }
        let deficit = total - available
        if slack >= deficit {
            let ratio = deficit / slack
            return zip(preferred, minimums).map { $0 - ($0 - $1) * ratio }
        }
        return preferred.map { $0 * available / total }
    }

    static func positions(for widths: [CGFloat]) -> [CGFloat] {
        var x: CGFloat = 0
        return widths.map { width in
            defer { x += width + spacing }
            return x
        }
    }
}

/// The Workspace: tool cards in a row. Drag a card by its top bar to reorder it,
/// or pull it out of the notch (down past the panel, or up into the menu bar) to remove it.
struct WorkspaceDashboard: View {
    private struct DragState {
        let tool: Tool
        let startX: CGFloat
        var translation: CGSize = .zero
        var removing = false
    }

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @State private var drag: DragState?

    var body: some View {
        let tools = store.dashboardTools
        if tools.isEmpty {
            emptyState
        } else {
            GeometryReader { proxy in
                let widths = DashboardLayout.widths(for: tools, in: proxy.size.width)
                let xs = DashboardLayout.positions(for: widths)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                        tile(tool, index: index, tools: tools, widths: widths, xs: xs, height: proxy.size.height)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .coordinateSpace(name: "dashboard")
                .animation(DS.spring, value: tools)
            }
        }
    }

    @ViewBuilder
    private func tile(_ tool: Tool, index: Int, tools: [Tool], widths: [CGFloat], xs: [CGFloat], height: CGFloat) -> some View {
        let dragged = drag?.tool == tool ? drag : nil
        let removing = dragged?.removing ?? false
        DashboardCard(tool: tool)
            .frame(width: widths[index], height: height)
            .overlay(alignment: .top) {
                DragBar(
                    isDragging: dragged != nil,
                    gesture: dragGesture(tool, tools: tools, widths: widths, xs: xs, height: height)
                )
                .accessibilityLabel("Move \(tool.title) card")
                .accessibilityAction(named: "Move Left") { store.moveOnDashboard(tool, by: -1) }
                .accessibilityAction(named: "Move Right") { store.moveOnDashboard(tool, by: 1) }
                .accessibilityAction(named: "Remove from Dashboard") { remove(tool) }
            }
            .overlay {
                if removing {
                    RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay {
                            Label("Release to remove", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .transition(.opacity)
                }
            }
            .scaleEffect(dragged == nil ? 1 : (removing ? 0.88 : 1.03))
            .opacity(removing ? 0.75 : 1)
            .shadow(color: .black.opacity(dragged == nil ? 0 : 0.45), radius: 16, y: 8)
            .offset(
                x: dragged.map { $0.startX + $0.translation.width } ?? xs[index],
                y: dragged?.translation.height ?? 0
            )
            .zIndex(dragged == nil ? 0 : 1)
            .animation(DS.snappy, value: removing)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private func dragGesture(_ tool: Tool, tools: [Tool], widths: [CGFloat], xs: [CGFloat], height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("dashboard"))
            .onChanged { value in
                guard let index = tools.firstIndex(of: tool) else { return }
                if drag?.tool != tool {
                    drag = DragState(tool: tool, startX: xs[index])
                    state.isPinned = true
                }
                guard var current = drag else { return }
                current.translation = value.translation
                current.removing = value.translation.height > height * 0.6 || value.translation.height < -70
                drag = current

                guard !current.removing else { return }
                let center = current.startX + value.translation.width + widths[index] / 2
                let others = tools.indices.filter { $0 != index }
                let target = others.filter { xs[$0] + widths[$0] / 2 < center }.count
                if target != index {
                    var order = tools
                    order.remove(at: index)
                    order.insert(tool, at: target)
                    withAnimation(DS.spring) { store.settings.dashboardTools = order.map(\.rawValue) }
                }
            }
            .onEnded { _ in
                let removing = drag?.removing ?? false
                withAnimation(DS.spring) {
                    if removing { remove(tool, announce: true) }
                    drag = nil
                }
                state.isPinned = false
            }
    }

    private func remove(_ tool: Tool, announce: Bool = false) {
        withAnimation(DS.spring) { store.settings.dashboardTools.removeAll { $0 == tool.rawValue } }
        if announce {
            state.post(Nudge(symbol: "rectangle.badge.minus", title: "Removed from Dashboard", subtitle: tool.title, tint: tool.tint, duration: 2))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.badge.plus").font(.system(size: 26))
            Text("Your dashboard is empty")
                .font(.system(size: 13, weight: .semibold))
            Text("Open any tool and choose ••• › Add to Dashboard.")
                .font(.system(size: 12))
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

/// Invisible grab area over a card's top pill; highlights the pill and shows a hand cursor.
private struct DragBar<G: Gesture>: View {
    let isDragging: Bool
    let gesture: G
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(Color.black.opacity(hovering || isDragging ? 0.4 : 0))
            .frame(width: hovering || isDragging ? 40 : 26, height: 4)
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 16, alignment: .top)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(gesture)
            .animation(DS.snappy, value: hovering || isDragging)
            .help("Drag to reorder · drag out of the notch to remove")
    }
}

/// The compact card a tool shows on the Workspace dashboard.
struct DashboardCard: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .tasks: TasksCard()
        case .focus: TimerCard()
        case .notepad: NotepadCard()
        case .calendar: EventsCard()
        case .week: WeekWidget()
        case .clips: ClipsWidget()
        case .clipboard: ClipboardWidget()
        case .insights: InsightsWidget()
        case .call: CallWidget()
        case .workspace, .settings, .neurons: EmptyView()
        }
    }
}

/// Title row for the compact widgets: title, then a ••• menu with "Open" and dashboard actions.
private struct WidgetHeader: View {
    let tool: Tool
    var title: String?
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack {
            CardTitle(title: title ?? tool.title, symbol: tool.symbol)
            Spacer(minLength: 0)
            Menu {
                Button("Open \(tool.title)") { withAnimation(DS.spring) { state.tool = tool } }
                Divider()
                DashboardMenuItems(tool: tool)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(tool.title) options")
        }
    }
}

private struct WeekWidget: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        Card(tint: DS.Palette.week) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(tool: .week, title: "This week")
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(days, id: \.self) { day in
                            let tasks = store.tasks(on: day, completed: false)
                            Button {
                                withAnimation(DS.spring) { state.tool = .week }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(DateText.relativeDay(day))
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 62, alignment: .leading)
                                    Text(tasks.first?.title ?? "—")
                                        .font(.system(size: 11))
                                        .foregroundStyle(tasks.isEmpty ? DS.inkTertiary : DS.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if tasks.count > 1 {
                                        Text("+\(tasks.count - 1)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(DS.inkSecondary)
                                    }
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(Calendar.current.isDateInToday(day) ? 0.55 : 0.3)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(DateText.relativeDay(day)), \(tasks.count) open task\(tasks.count == 1 ? "" : "s")")
                        }
                    }
                }
            }
        }
    }
}

private struct ClipsWidget: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState

    var body: some View {
        let recent = Array(store.clips.sorted { $0.createdAt > $1.createdAt }.prefix(4))
        Card(tint: DS.Palette.clips) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(tool: .clips)
                if recent.isEmpty {
                    Text("No captures yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(recent) { MiniClipThumbnail(clip: $0) }
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    state.captureClip(.region)
                } label: {
                    Label("Capture", systemImage: "plus.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkCapsuleButtonStyle())
                .help("Capture region (⇧⌘C)")
            }
        }
    }
}

private struct MiniClipThumbnail: View {
    let clip: Clip
    @EnvironmentObject private var clips: ClipService
    @EnvironmentObject private var state: AppState
    @State private var image: NSImage?

    var body: some View {
        Button {
            clips.copy(clip)
            state.post(Nudge(symbol: "doc.on.clipboard", title: "Copied to clipboard", tint: DS.Palette.clips, sound: "Pop", duration: 2))
        } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.08)
                }
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Click to copy")
        .task(id: clip.id) { image = await Thumbnailer.thumbnail(for: clips.url(for: clip), maxPixelSize: 200) }
        .accessibilityLabel("Clip from \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Copies to the clipboard")
    }
}

private struct ClipboardWidget: View {
    @EnvironmentObject private var clipboard: ClipboardHistory
    @EnvironmentObject private var state: AppState

    var body: some View {
        let recent = Array((clipboard.items.filter(\.isPinned) + clipboard.items.filter { !$0.isPinned }).prefix(6))
        Card(tint: DS.Palette.clipboard) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(tool: .clipboard)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(recent) { item in
                            Button {
                                clipboard.copy(item)
                                state.post(Nudge(symbol: "doc.on.clipboard.fill", title: "Copied", tint: DS.Palette.clipboard, sound: "Pop", duration: 1.8))
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: item.isPinned ? "pin.fill" : symbol(item.kind))
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.inkSecondary)
                                    Text(preview(item))
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.35)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Click to copy")
                            .accessibilityLabel("Copy \(preview(item))")
                        }
                        if recent.isEmpty {
                            Text("Copy something and it shows up here.")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.inkTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ kind: ClipboardItem.Kind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private func preview(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return "Image"
        case .file: return (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.joined(separator: ", ")
        default: return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        }
    }
}

private struct InsightsWidget: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let summary = InsightsSummary.compute(tasks: store.tasks, sessions: store.sessions)
        Card(tint: DS.Palette.insights) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(tool: .insights)
                HStack(spacing: 6) {
                    stat("\(summary.currentStreak)", "streak", "flame.fill")
                    stat("\(summary.completedToday)", "done today", "checkmark.circle.fill")
                    stat(DateText.minutes(summary.focusMinutesToday), "focus", "bolt.fill")
                }
                Chart(summary.days.suffix(7)) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Completed", day.completed))
                        .foregroundStyle(DS.ink.opacity(Calendar.current.isDateInToday(day.date) ? 0.9 : 0.5))
                        .cornerRadius(3)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                }
                .accessibilityLabel("Completed tasks over the last 7 days")
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 9.5)).foregroundStyle(DS.inkSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CallWidget: View {
    @EnvironmentObject private var calls: CallRecorder

    var body: some View {
        Card(tint: DS.Palette.call) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(tool: .call)
                Text(calls.teamsRunning ? "Teams is open" : "Open Teams on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.inkSecondary)
                if calls.isRecording {
                    Text(calls.elapsedText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Button {
                    Task { await calls.toggle() }
                } label: {
                    Label(calls.isRecording ? "Stop" : "Record call", systemImage: calls.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkCapsuleButtonStyle(prominent: true))
                .disabled(calls.phase == .preparing || calls.phase == .saving)
            }
        }
        .onAppear { calls.refreshPresence() }
    }
}
