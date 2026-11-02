import SwiftUI

/// Everything drawn inside the transparent notch window: the black island (closed, timer,
/// nudge or open panel) and, when open, the floating tool dock beneath it.
struct NotchRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var store: Store

    private enum Mode: Equatable { case hidden, idle, timer, nudge, open }

    private var layout: NotchLayout { state.layout }

    private var mode: Mode {
        if state.isOpen { return .open }
        if state.nudge != nil { return .nudge }
        if timer.isActive && layout.hasNotch { return .timer }
        return layout.hasNotch ? .idle : .hidden
    }

    private var islandSize: CGSize {
        let notch = layout.notchSize
        let flare = layout.hasNotch ? layout.notchTopRadius * 2 : 0
        switch mode {
        case .open:
            return layout.openPanelSize(for: state.tool)
        case .nudge:
            return CGSize(width: max(notch.width + 220, 400), height: (layout.hasNotch ? notch.height : 0) + 56)
        case .timer:
            return CGSize(width: notch.width + 150 + flare, height: notch.height)
        case .idle:
            return CGSize(width: notch.width + NotchLayout.mascotWing * 2 + flare, height: notch.height)
        case .hidden:
            return CGSize(width: 220, height: 0)
        }
    }

    private var islandShape: AnyShape {
        let open = mode == .open
        if layout.hasNotch {
            return AnyShape(NotchShape(topRadius: layout.notchTopRadius, bottomRadius: open ? 28 : (mode == .nudge ? 22 : 12)))
        }
        return AnyShape(RoundedRectangle(cornerRadius: open ? 26 : 22, style: .continuous))
    }

    var body: some View {
        VStack(spacing: 12) {
            island
            if mode == .open && store.settings.showToolDock {
                ToolDock()
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .padding(.top, mode == .hidden || layout.hasNotch ? 0 : layout.panelTopOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(DS.spring, value: mode)
        .preferredColorScheme(.dark)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            switch mode {
            case .open:
                PanelView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)).animation(.easeOut(duration: 0.14)))
            case .nudge:
                if let nudge = state.nudge {
                    NudgeBanner(nudge: nudge, topInset: layout.hasNotch ? layout.notchSize.height : 0)
                        .transition(.opacity)
                }
            case .timer:
                NotchTimerIndicator()
                    .transition(.opacity)
            case .idle:
                HStack(spacing: 0) {
                    HappyMascot(size: min(20, layout.notchSize.height - 12))
                        .frame(width: NotchLayout.mascotWing)
                    Color.clear.frame(width: layout.notchSize.width)
                    Color.clear.frame(width: NotchLayout.mascotWing)
                }
                .frame(height: layout.notchSize.height)
                .transition(.opacity)
            case .hidden:
                EmptyView()
            }
        }
        .frame(width: islandSize.width, height: islandSize.height, alignment: .top)
        .animation(DS.spring, value: state.tool)
        .background(islandShape.fill(Color.black))
        .clipShape(islandShape)
        .shadow(color: .black.opacity(mode == .open || mode == .nudge ? 0.45 : 0), radius: 20, y: 10)
        .opacity(mode == .hidden ? 0 : 1)
        .contentShape(islandShape)
        .onTapGesture {
            if mode == .nudge { state.dismissNudge() }
        }
    }
}

// MARK: - Open panel

struct PanelView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            PanelHeader()
            ToolContentView(tool: state.tool)
                .environment(\.isNotchPanel, true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(state.tool)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
        }
        .padding(.horizontal, state.layout.hasNotch ? state.layout.notchTopRadius + 14 : 16)
        .padding(.top, state.layout.hasNotch ? 0 : 6)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            if let nudge = state.nudge {
                NudgeToast(nudge: nudge)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct PanelHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.layout.hasNotch {
                HStack(spacing: 0) {
                    leading.frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: state.layout.notchSize.width + 16)
                    trailing.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack {
                    leading
                    Spacer()
                    trailing
                }
            }
        }
        .frame(height: state.layout.headerHeight)
    }

    private var leading: some View {
        HStack(spacing: 8) {
            AppBadge()
            Text(AppInfo.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            HeaderIconButton(symbol: "macwindow", label: "Open dashboard window (⌘D)") {
                state.openDashboard(state.tool)
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach([Tool.workspace, .insights, .settings]) { tool in
                    let selected = state.tool == tool
                    Button {
                        withAnimation(DS.spring) { state.tool = tool }
                    } label: {
                        Text(tool.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help("\(tool.title) (\(tool.shortcut))")
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.07)))

            if state.tool != .settings {
                ToolOptionsMenu(tool: state.tool)
            }
            HeaderIconButton(symbol: "xmark", label: "Close (Esc)") { state.requestClose() }
        }
    }
}

struct AppBadge: View {
    var size: CGFloat = 22

    var body: some View {
        HappyMascot(size: size)
    }
}

struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Closed states

struct NotchTimerIndicator: View {
    @EnvironmentObject private var timer: FocusTimer
    @EnvironmentObject private var state: AppState

    var body: some View {
        TimerIndicatorContent(
            clock: timer.clock,
            paused: timer.phase == .paused,
            notchWidth: state.layout.notchSize.width,
            height: state.layout.notchSize.height,
            inset: state.layout.notchTopRadius
        )
    }
}

private struct TimerIndicatorContent: View {
    @ObservedObject var clock: FocusClock
    let paused: Bool
    let notchWidth: CGFloat
    let height: CGFloat
    let inset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().stroke(DS.Palette.focus.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: clock.progress)
                    .stroke(DS.Palette.focus, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: paused ? "pause.fill" : "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DS.Palette.focus)
            }
            .frame(width: 16, height: 16)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            Text(clock.display)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.focus.opacity(paused ? 0.6 : 1))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, inset)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? "Focus timer paused at \(clock.display)" : "Focus timer \(clock.display)")
    }
}

struct NudgeBanner: View {
    let nudge: Nudge
    let topInset: CGFloat
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(nudge.tint.opacity(0.22))
                Image(systemName: nudge.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(nudge.tint)
            }
            .frame(width: 34, height: 34)
            .scaleEffect(pulse ? 1.1 : 0.92)

            VStack(alignment: .leading, spacing: 1) {
                Text(nudge.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle = nudge.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, topInset + 8)
        .padding(.bottom, 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatCount(4, autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NudgeToast: View {
    let nudge: Nudge

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: nudge.symbol).foregroundStyle(nudge.tint)
            Text(nudge.title).fontWeight(.semibold)
            if let subtitle = nudge.subtitle {
                Text(subtitle).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}
