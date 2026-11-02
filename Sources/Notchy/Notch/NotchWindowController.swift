import AppKit
import Combine
import SwiftUI

/// Owns the notch panel and decides when it opens and closes.
///
/// The panel stays on screen permanently so opening is just a state flip (no window creation).
/// While closed it ignores mouse events, and hover is detected with event monitors, so it
/// never blocks clicks on the menu bar.
@MainActor
final class NotchWindowController: NSObject {
    let panel: NotchPanel
    private let services: Services
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var screenFrame: NSRect = .zero
    private var shrinkWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private var state: AppState { services.state }

    init(services: Services) {
        self.services = services
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: NotchLayout.windowSize))
        super.init()

        let host = NSHostingView(rootView: NotchRootView().environmentServices(services))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onResignKey = { [weak self] in self?.handleResignKey() }

        reposition()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
                self?.panel.orderFrontRegardless()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(state.$tool, state.$isOpen)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.applyFrame(animated: true) }
            .store(in: &cancellables)
    }

    // MARK: Open / close

    func toggle() {
        if state.isOpen && panel.isKeyWindow {
            close()
        } else {
            open(fromKeyboard: true)
        }
    }

    func open(fromKeyboard: Bool) {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        if !state.isOpen {
            reposition()
            panel.ignoresMouseEvents = false
            state.isOpen = true
        }
        if fromKeyboard {
            panel.makeKeyAndOrderFront(nil)
            state.focusQuickAdd()
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        guard state.isOpen else { return }
        state.isOpen = false
        panel.ignoresMouseEvents = true
        services.speech.stop()
        // Hand keyboard focus back to the previously active app once the close animation ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.state.isOpen, self.panel.isKeyWindow else { return }
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
        }
    }

    private func handleResignKey() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.isOpen, !self.state.isPinned, !self.panel.isKeyWindow else { return }
            if self.panel.attachedSheet != nil { return }
            self.close()
        }
    }

    // MARK: Geometry

    private func reposition() {
        applyFrame(animated: false)
    }

    /// Grows the window as soon as Neurons opens, and shrinks it only after the island has animated down.
    private func applyFrame(animated: Bool) {
        shrinkWork?.cancel()
        shrinkWork = nil
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let layout = NotchGeometry(screen: screen).layout
        if state.layout != layout { state.layout = layout }
        screenFrame = screen.frame
        let tool: Tool = state.isOpen ? state.tool : .workspace
        let size = layout.windowSize(for: tool, screenHeight: screen.frame.height)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        guard panel.frame != frame else { return }
        if animated, frame.height < panel.frame.height {
            let work = DispatchWorkItem { [weak self] in self?.applyFrame(animated: false) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            return
        }
        panel.setFrame(frame, display: false)
    }

    /// Area that opens the panel on hover: the notch (plus the timer indicator if visible),
    /// or a strip at the top centre of the menu bar on Macs without a notch.
    private var hotRect: NSRect {
        let layout = state.layout
        let width: CGFloat
        let height: CGFloat
        if layout.hasNotch {
            let extended = services.timer.isActive || services.calls.isRecording
            width = layout.notchSize.width + (extended ? 150 : NotchLayout.mascotWing * 2)
            height = layout.notchSize.height
        } else {
            width = 220
            height = max(layout.menuBarHeight, 6)
        }
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height + 1)
    }

    /// Panel plus the floating tool dock below it.
    private var interactiveRect: NSRect {
        let layout = state.layout
        let height = layout.panelTopOffset + layout.openPanelSize(for: state.tool).height + 12 + NotchLayout.dockHeight + 30
        let width = NotchLayout.panelWidth + 24
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height + 1)
    }

    // MARK: Event monitors

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.handleMouseMoved()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.handleMouseMoved()
            return event
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.handleClickOutside()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }) { monitors.append(m) }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        if state.isOpen {
            if interactiveRect.contains(point) {
                closeWork?.cancel()
                closeWork = nil
            } else if !panel.isKeyWindow, !state.isPinned, NSEvent.pressedMouseButtons == 0, closeWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.interactiveRect.contains(NSEvent.mouseLocation), !self.panel.isKeyWindow { self.close() }
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
            return
        }

        guard services.store.settings.hoverToOpen else { return }
        if hotRect.contains(point) {
            guard openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                if self.hotRect.contains(NSEvent.mouseLocation) { self.open(fromKeyboard: false) }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
        }
    }

    private func handleClickOutside() {
        guard state.isOpen, !state.isPinned, !interactiveRect.contains(NSEvent.mouseLocation) else { return }
        close()
    }

    /// Panel-wide shortcuts. Returns true when the event was handled.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow, state.isOpen else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {
            close()
            return true
        }
        guard flags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command, let digit = Int(key) {
            let index = digit == 0 ? 9 : digit - 1
            guard Tool.allCases.indices.contains(index) else { return false }
            withAnimation(DS.spring) { state.tool = Tool.allCases[index] }
            return true
        }
        switch (key, flags == [.command, .shift]) {
        case (",", false):
            withAnimation(DS.spring) { state.tool = .settings }
        case ("n", false):
            state.focusQuickAdd()
        case ("t", false):
            services.timer.toggle()
        case ("d", false):
            state.openDashboard(nil)
        case ("w", false):
            close()
        case ("c", true):
            state.captureClip(.region)
        case ("m", true):
            state.startDictation()
        default:
            return false
        }
        return true
    }
}
