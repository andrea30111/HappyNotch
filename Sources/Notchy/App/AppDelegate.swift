import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var services: Services!
    private var notch: NotchWindowController!
    private var statusItem: NSStatusItem?
    private var dashboardWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private struct MCPConfig: Equatable {
        let enabled: Bool
        let port: Int
        let token: String
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let services = Services()
        self.services = services
        notch = NotchWindowController(services: services)

        let state = services.state
        state.requestOpen = { [weak self] in self?.notch.open(fromKeyboard: false) }
        state.requestClose = { [weak self] in self?.notch.close() }
        state.openDashboard = { [weak self] tool in self?.showDashboard(tool: tool) }
        state.captureClip = { [weak self] mode in self?.captureClip(mode) }

        HotKeyManager.shared.onTrigger = { [weak self] in self?.notch.toggle() }
        services.store.$settings
            .map(\.hotKey)
            .removeDuplicates()
            .sink { HotKeyManager.shared.register($0) }
            .store(in: &cancellables)

        services.store.$settings
            .map { MCPConfig(enabled: $0.mcpEnabled, port: $0.mcpPort, token: $0.mcpToken) }
            .removeDuplicates()
            .sink { [weak self] config in
                guard let mcp = self?.services.mcp else { return }
                if config.enabled {
                    mcp.start(port: config.port, token: config.token)
                } else {
                    mcp.stop()
                }
            }
            .store(in: &cancellables)

        setupStatusItem()

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            showPermissions()
        }

        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            renderSnapshot(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        #endif
    }

    #if DEBUG
    /// Renders the open panel to a PNG (used to check layout without Screen Recording access).
    private func renderSnapshot(to url: URL) {
        if let tools = ProcessInfo.processInfo.environment["NOTCHY_DASHBOARD"] {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("notchy-snapshot-\(UUID().uuidString).json")
            let store = Store(fileURL: temp)
            store.settings.dashboardTools = tools.split(separator: ",").map(String.init)
            services = Services(store: store)
        }
        let state = services.state
        state.layout = NotchLayout(hasNotch: true, notchSize: CGSize(width: 185, height: 32), menuBarHeight: 32)
        if let tool = ProcessInfo.processInfo.environment["NOTCHY_TOOL"].flatMap(Tool.init(rawValue:)) { state.tool = tool }
        state.isOpen = ProcessInfo.processInfo.environment["NOTCHY_CLOSED"] == nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [services] in
            guard let services else { return }
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.75, green: 0.6, blue: 0.4)], startPoint: .top, endPoint: .bottom)
                NotchRootView().environmentServices(services)
            }
            .frame(width: state.layout.windowSize(for: state.tool, screenHeight: 1200).width,
                   height: state.layout.windowSize(for: state.tool, screenHeight: 1200).height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            NSApp.terminate(nil)
        }
    }
    #endif

    /// `notchy://open[?tool=week]`, `notchy://add?text=…`, `notchy://dashboard`, `notchy://capture`
    /// for Shortcuts, Raycast and similar launchers.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "notchy" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let tool = query.first { $0.name == "tool" }?.value.flatMap(Tool.init(rawValue:))
            switch url.host {
            case "open":
                if let tool { services.state.tool = tool }
                notch.open(fromKeyboard: true)
            case "add":
                if let text = query.first(where: { $0.name == "text" })?.value, let task = services.store.addTask(text: text) {
                    services.state.post(Nudge(symbol: "checklist", title: "Task added", subtitle: task.title, tint: DS.Palette.tasks, sound: "Pop", duration: 2.5))
                }
            case "dashboard":
                showDashboard(tool: tool)
            case "capture":
                captureClip(.region)
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if services.timer.isActive { services.timer.finish() }
        services.store.saveNow()
        services.clipboard.saveNow()
        services.mcp.stop()
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = HappyMascot.templateImage()
            ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: AppInfo.name)
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(makeItem("Open \(AppInfo.name)", #selector(openPanel), key: ""))
        menu.addItem(makeItem("Dashboard…", #selector(openDashboardFromMenu), key: "d"))
        menu.addItem(makeItem("Capture Clip", #selector(captureFromMenu), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettingsFromMenu), key: ","))
        menu.addItem(makeItem("Permissions…", #selector(showPermissions), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit \(AppInfo.name)", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        item.menu = menu
        statusItem = item

        // Macs without a notch show the running timer in the menu bar instead.
        services.timer.clock.$display
            .combineLatest(services.timer.$phase, services.state.$layout)
            .receive(on: RunLoop.main)
            .sink { [weak item] display, phase, layout in
                let active = phase == .running || phase == .paused
                item?.button?.title = active && !layout.hasNotch ? " \(display)" : ""
            }
            .store(in: &cancellables)
    }

    private func makeItem(_ title: String, _ action: Selector, key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func openPanel() { notch.open(fromKeyboard: true) }
    @objc private func openDashboardFromMenu() { showDashboard(tool: nil) }
    @objc private func openSettingsFromMenu() { showDashboard(tool: .settings) }
    @objc private func captureFromMenu() { captureClip(.region) }

    // MARK: Actions

    private func captureClip(_ mode: ClipService.Mode) {
        notch.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.services.clips.capture(mode)
        }
    }

    private func showDashboard(tool: Tool?) {
        notch.close()
        if let tool { services.state.dashboardTool = tool }
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppInfo.name) Dashboard"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 960, height: 600)
            window.contentView = NSHostingView(rootView: DashboardView().environmentServices(services))
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("NotchyDashboard")
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func showPermissions() {
        notch.close()
        if permissionsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            let root = PermissionsOnboardingView { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                self?.permissionsWindow?.close()
            }
            .environmentServices(services)
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.delegate = self
            window.center()
            permissionsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        permissionsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        guard closing === dashboardWindow || closing === permissionsWindow else { return }
        if closing === permissionsWindow { UserDefaults.standard.set(true, forKey: "onboardingCompleted") }
        let othersVisible = [dashboardWindow, permissionsWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !othersVisible { NSApp.setActivationPolicy(.accessory) }
    }

    /// Accessory apps still need an Edit menu for ⌘C / ⌘V / ⌘Z to work in text fields.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
