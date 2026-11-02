import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case permissions = "Permissions"
        case focus = "Focus"
        case sync = "Apple Calendar, Reminders & Notes"
        case voice = "Voice"
        case agents = "AI Agents"
        case data = "Data & Privacy"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .permissions: return "hand.raised"
            case .focus: return "timer"
            case .sync: return "arrow.triangle.2.circlepath"
            case .voice: return "mic"
            case .agents: return "sparkles"
            case .data: return "lock.shield"
            }
        }
    }

    @State private var section: Section = .general

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Section.allCases) { item in
                    let selected = item == section
                    Button {
                        section = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected ? 0.12 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .frame(width: 190)

            Group {
                switch section {
                case .general: GeneralSettings()
                case .permissions:
                    ScrollView { PermissionsList().padding(12) }
                case .focus: FocusSettings()
                case .sync: SyncSettings()
                case .voice: VoiceSettings()
                case .agents: AgentSettings()
                case .data: DataSettings()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        }
        .font(.system(size: 12))
    }
}

// MARK: - Sections

private struct GeneralSettings: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open when hovering over the notch", isOn: $store.settings.hoverToOpen)
                Picker("Global shortcut", selection: $store.settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show floating tool icons", isOn: $store.settings.showToolDock)
            }
            Section("Notch nudges") {
                Toggle("Show nudges for due tasks and timers", isOn: $store.settings.nudgesEnabled)
                Toggle("Play a sound", isOn: $store.settings.nudgeSound)
                    .disabled(!store.settings.nudgesEnabled)
                Button("Preview nudge") {
                    state.post(Nudge(symbol: "bell.fill", title: "Due now", subtitle: "Review Sam's PR", tint: DS.Palette.tasks))
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Button("Open dashboard window") { state.openDashboard(.workspace) }
            }
            Section("Keyboard") {
                LabeledContent("Open / close", value: store.settings.hotKey.label)
                LabeledContent("Switch tool", value: "⌘1 … ⌘9")
                LabeledContent("New task · Dictate", value: "⌘N · ⇧⌘M")
                LabeledContent("Start / pause focus", value: "⌘T")
                LabeledContent("Capture clip · Dashboard", value: "⇧⌘C · ⌘D")
                LabeledContent("Note line → task", value: "⌘↩")
            }
        }
    }
}

private struct FocusSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Form {
            Section("Defaults") {
                Stepper(value: $store.settings.defaultFocusMinutes, in: 5...180, step: 5) {
                    LabeledContent("Session length", value: "\(store.settings.defaultFocusMinutes) min")
                }
                Picker("Mode", selection: $store.settings.defaultTimerMode) {
                    ForEach(TimerMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Pause automatically when the Mac sleeps", isOn: $store.settings.autoPauseOnSleep)
            } footer: {
                Text("While a timer runs, a compact indicator stays next to the notch (or in the menu bar on Macs without one).")
            }
        }
    }
}

private struct SyncSettings: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var reminders: RemindersSync
    @EnvironmentObject private var notesSync: AppleNotesSync

    var body: some View {
        Form {
            Section {
                LabeledContent("Calendar") {
                    if calendar.hasAccess {
                        Label("Connected (read-only)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if calendar.isDenied {
                        Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                    } else {
                        Button("Connect") { calendar.requestAccess() }
                    }
                }
            } footer: {
                Text("HappyNotch only reads events to show today's schedule. It never creates, edits or deletes them.")
            }

            Section {
                Toggle("Sync tasks with Apple Reminders", isOn: Binding(
                    get: { store.settings.remindersSyncEnabled },
                    set: { reminders.setEnabled($0) }
                ))
                if store.settings.remindersSyncEnabled {
                    Picker("List", selection: Binding(
                        get: { store.settings.remindersListID ?? "" },
                        set: { reminders.selectList($0) }
                    )) {
                        ForEach(reminders.lists) { Text($0.title).tag($0.id) }
                    }
                    LabeledContent("Last synced") {
                        if reminders.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(reminders.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                        }
                    }
                    Button("Sync now") { Task { await reminders.sync() } }
                }
                if let error = reminders.lastError {
                    Text(error).foregroundStyle(.orange).font(.caption)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Off by default. When on, tasks sync two-way with one Reminders list, so they reach your iPhone and Apple Watch through iCloud. Nothing else leaves your Mac.")
            }

            Section {
                Toggle("Sync the notepad with Apple Notes", isOn: Binding(
                    get: { store.settings.appleNotesSyncEnabled },
                    set: { notesSync.setEnabled($0) }
                ))
                if store.settings.appleNotesSyncEnabled {
                    LabeledContent("Last synced") {
                        if notesSync.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(notesSync.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                        }
                    }
                    HStack {
                        Button("Sync now") { Task { await notesSync.sync() } }
                        if notesSync.needsPermission {
                            Button("Open Automation Settings") { notesSync.openAutomationSettings() }
                        }
                    }
                }
                if let error = notesSync.lastError {
                    Text(error).foregroundStyle(.orange).font(.caption)
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("Pages lists every note in Apple Notes. Sync is off by default: each day's page then becomes a note \"Notchy · date\" in a \"Notchy\" folder, and edits flow both ways. If both sides change at once, the notepad wins. HappyNotch only creates or edits those daily notes. macOS will ask once to let HappyNotch control Notes.")
            }
        }
    }
}

private struct VoiceSettings: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: SpeechService

    var body: some View {
        Form {
            Section {
                LabeledContent("On-device recognition") {
                    Text(speech.supportsOnDevice ? "Available" : "Not available for \(Locale.current.identifier)")
                        .foregroundStyle(speech.supportsOnDevice ? .green : .orange)
                }
                Toggle("Allow Apple's server recognition as a fallback", isOn: $store.settings.allowServerSpeechRecognition)
            } footer: {
                Text("Dictation runs on-device whenever possible. The fallback sends audio to Apple only when on-device recognition isn't available for your language.")
            }
            if let error = speech.lastError {
                Section { Text(error).foregroundStyle(.orange) }
            }
        }
    }
}

private struct AgentSettings: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var mcp: MCPServer
    @State private var revealToken = false
    @State private var copied: String?

    private var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/HappyNotch.app/Contents/MacOS/HappyNotch"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable local MCP server", isOn: $store.settings.mcpEnabled)
                LabeledContent("Status") {
                    if store.settings.mcpEnabled {
                        Label(mcp.isRunning ? "Running on 127.0.0.1:\(String(store.settings.mcpPort))" : "Starting…",
                              systemImage: mcp.isRunning ? "dot.radiowaves.left.and.right" : "hourglass")
                            .foregroundStyle(mcp.isRunning ? .green : .secondary)
                    } else {
                        Text("Off").foregroundStyle(.secondary)
                    }
                }
                if let error = mcp.lastError { Text(error).foregroundStyle(.orange).font(.caption) }
            } footer: {
                Text("Lets AI agents (Claude, Cursor, …) read and add tasks, notes and focus sessions. Calendar access is read-only. The server only listens on this Mac and requires a token.")
            }

            Section("Connection") {
                TextField("Port", value: $store.settings.mcpPort, format: .number.grouping(.never))
                LabeledContent("Token") {
                    HStack {
                        Text(revealToken ? store.settings.mcpToken : String(repeating: "•", count: 16))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button(revealToken ? "Hide" : "Show") { revealToken.toggle() }
                        Button("Regenerate") { store.settings.mcpToken = Token.generate() }
                    }
                }
                HStack {
                    Button("Copy stdio config") { copy(stdioConfig, label: "stdio") }
                    Button("Copy HTTP config") { copy(httpConfig, label: "http") }
                    if let copied { Text("Copied \(copied) config").foregroundStyle(.secondary).font(.caption) }
                }
            }

            Section("Connected agents") {
                if mcp.clients.isEmpty {
                    Text("No agents have connected yet.").foregroundStyle(.secondary)
                }
                ForEach(mcp.clients) { client in
                    LabeledContent("\(client.name) \(client.version)") {
                        Text(client.lastSeen.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var stdioConfig: String {
        """
        {
          "mcpServers": {
            "happynotch": {
              "command": "\(executablePath)",
              "args": ["--mcp-stdio"]
            }
          }
        }
        """
    }

    private var httpConfig: String {
        """
        {
          "mcpServers": {
            "happynotch": {
              "url": "http://127.0.0.1:\(store.settings.mcpPort)/mcp",
              "headers": { "Authorization": "Bearer \(store.settings.mcpToken)" }
            }
          }
        }
        """
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }
}

private struct DataSettings: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var clipboard: ClipboardHistory
    @EnvironmentObject private var state: AppState
    @State private var message: String?
    @State private var confirmErase = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Storage", value: "On this Mac only")
                LabeledContent("Tasks · Notes · Sessions", value: "\(store.tasks.count) · \(store.notes.count) · \(store.sessions.count)")
                Button("Show data folder") { NSWorkspace.shared.open(Store.supportDirectory) }
            } footer: {
                Text("Everything is stored locally in Application Support. Cloud sync only happens if you turn on Reminders or Apple Notes sync.")
            }
            Section {
                Toggle("Keep clipboard history (last \(ClipboardHistory.limit) items)", isOn: $store.settings.clipboardHistoryEnabled)
                Button("Clear clipboard history") { clipboard.clear(keepPinned: false) }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Stored only on this Mac and never exported. Items marked as concealed by password managers are skipped.")
            }
            Section("Backup") {
                HStack {
                    Button("Export JSON…", action: exportData)
                    Button("Import JSON…", action: importData)
                }
                if let message { Text(message).foregroundStyle(.secondary).font(.caption) }
            }
            Section {
                if confirmErase {
                    HStack {
                        Text("Delete all tasks, notes, sessions and clips?")
                        Spacer()
                        Button("Cancel") { confirmErase = false }
                        Button("Erase", role: .destructive) {
                            store.eraseAll()
                            clipboard.clear(keepPinned: false)
                            confirmErase = false
                            message = "All data erased."
                        }
                    }
                } else {
                    Button("Erase all data…", role: .destructive) { confirmErase = true }
                }
            }
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HappyNotch Backup \(DayKey.key(for: Date())).json"
        runPanel(panel) { url in
            try store.exportData(to: url)
            message = "Exported to \(url.lastPathComponent)"
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        runPanel(panel) { url in
            try store.importData(from: url)
            message = "Imported \(store.tasks.count) tasks."
        }
    }

    /// Keeps the notch panel open while the system file panel has focus.
    private func runPanel(_ panel: NSSavePanel, onURL: @escaping (URL) throws -> Void) {
        state.isPinned = true
        NSApp.activate()
        panel.begin { response in
            defer { state.isPinned = false }
            guard response == .OK, let url = panel.url else { return }
            do {
                try onURL(url)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
