import AppKit
import SwiftUI

struct Nudge: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color
    var sound: String = "Tink"
    var duration: TimeInterval = 4.5

    static func == (lhs: Nudge, rhs: Nudge) -> Bool { lhs.id == rhs.id }
}

/// Where the notch is and how big the island gets. Computed from the screen the panel lives on.
struct NotchLayout: Equatable {
    var hasNotch: Bool
    var notchSize: CGSize
    var menuBarHeight: CGFloat

    static let panelWidth: CGFloat = 900
    static let contentHeight: CGFloat = 300
    static let dockHeight: CGFloat = 44
    /// Extra black on each side of the closed notch; the left one holds the mascot.
    static let mascotWing: CGFloat = 30
    static let windowSize = CGSize(width: 1000, height: 540)
    static let fallback = NotchLayout(hasNotch: false, notchSize: CGSize(width: 200, height: 24), menuBarHeight: 24)

    var headerHeight: CGFloat { hasNotch ? max(notchSize.height, 32) : 36 }
    var openPanelSize: CGSize { CGSize(width: Self.panelWidth, height: headerHeight + 8 + Self.contentHeight + 14) }
    var panelTopOffset: CGFloat { hasNotch ? 0 : menuBarHeight + 6 }
    var notchTopRadius: CGFloat { 8 }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isOpen = false
    @Published var tool: Tool = .workspace
    @Published var dashboardTool: Tool? = .workspace
    @Published var layout = NotchLayout.fallback
    @Published var nudge: Nudge?
    @Published var isPinned = false
    @Published var notepadDay = Calendar.current.startOfDay(for: Date())
    @Published var focusQuickAddToken = 0
    @Published var dictateToken = 0

    var requestOpen: () -> Void = {}
    var requestClose: () -> Void = {}
    var openDashboard: (Tool?) -> Void = { _ in }
    var captureClip: (ClipService.Mode) -> Void = { _ in }

    private let store: Store
    private var dismissWork: DispatchWorkItem?

    init(store: Store) {
        self.store = store
    }

    /// Shows a Live-Activity style nudge in the notch, with an optional sound, a trackpad haptic
    /// and a VoiceOver announcement.
    func post(_ nudge: Nudge) {
        guard store.settings.nudgesEnabled else { return }
        withAnimation(DS.spring) { self.nudge = nudge }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if store.settings.nudgeSound { NSSound(named: NSSound.Name(nudge.sound))?.play() }
        let announcement = [nudge.title, nudge.subtitle].compactMap { $0 }.joined(separator: ", ")
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(DS.spring) { self?.nudge = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + nudge.duration, execute: work)
    }

    func dismissNudge() {
        dismissWork?.cancel()
        withAnimation(DS.spring) { nudge = nil }
    }

    /// Switches to a tool that contains the quick-add field and focuses it.
    func focusQuickAdd() {
        if tool != .tasks && tool != .workspace { tool = .workspace }
        focusQuickAddToken += 1
    }

    func startDictation() {
        if tool != .tasks && tool != .workspace { tool = .workspace }
        dictateToken += 1
    }
}
