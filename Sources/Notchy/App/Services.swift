import Combine
import SwiftUI

/// Owns every long-lived service so the panel, dashboard and MCP server share one state.
@MainActor
final class Services {
    let store: Store
    let state: AppState
    let timer: FocusTimer
    let speech: SpeechService
    let calendar: CalendarService
    let reminders: RemindersSync
    let clips: ClipService
    let mcp: MCPServer
    let scheduler: ReminderScheduler
    let permissions: PermissionsCenter
    let clipboard: ClipboardHistory
    let notesSync: AppleNotesSync
    let calls: CallRecorder
    private var cancellables = Set<AnyCancellable>()

    init(store: Store? = nil) {
        let store = store ?? Store()
        let state = AppState(store: store)
        let timer = FocusTimer(store: store)
        let speech = SpeechService(store: store)
        let calendar = CalendarService()
        let clips = ClipService(store: store)

        self.store = store
        self.state = state
        self.timer = timer
        self.speech = speech
        self.calendar = calendar
        self.clips = clips
        let reminders = RemindersSync(store: store)
        self.reminders = reminders
        let notesSync = AppleNotesSync(store: store)
        self.notesSync = notesSync
        state.$isOpen
            .filter { $0 }
            .sink { _ in notesSync.refreshIfStale() }
            .store(in: &cancellables)
        let calls = CallRecorder()
        self.calls = calls
        permissions = PermissionsCenter(calendar: calendar, reminders: reminders)
        clipboard = ClipboardHistory(store: store)
        scheduler = ReminderScheduler(store: store, state: state)
        mcp = MCPServer(toolbox: MCPToolbox(store: store, timer: timer, calendar: calendar))

        timer.onFinish = { [weak state] timer in
            let title = timer.task?.title ?? "Nice work — take a short break."
            state?.post(Nudge(symbol: "checkmark.seal.fill", title: "Focus complete", subtitle: title, tint: DS.Palette.focus, sound: "Glass", duration: 6))
        }
        timer.onSleepPause = { [weak state] in
            state?.post(Nudge(symbol: "pause.circle.fill", title: "Focus paused while your Mac slept", subtitle: "Resume from the notch when you're ready.", tint: DS.Palette.focus))
        }
        clips.onSaved = { [weak state, weak store] _ in
            let copied = store?.settings.copyClipsToClipboard ?? false
            state?.post(Nudge(symbol: "camera.viewfinder", title: "Clip saved", subtitle: copied ? "Copied to the clipboard" : nil, tint: DS.Palette.clips, sound: "Pop", duration: 3))
        }
        speech.onAuthorizationPrompt = { [weak state] waiting in
            state?.isPinned = waiting
        }
        calls.onBegan = { [weak state] in
            state?.post(Nudge(
                symbol: "phone.fill",
                title: "Recording Teams",
                subtitle: "Tell the other people — Teams won't notify them.",
                tint: DS.Palette.call,
                duration: 5
            ))
        }
        calls.onSaved = { [weak state] in
            state?.post(Nudge(symbol: "phone.fill", title: "Call saved", subtitle: "Saved on this Mac", tint: DS.Palette.call, sound: "Pop", duration: 3))
        }
    }
}

extension View {
    func environmentServices(_ services: Services) -> some View {
        self
            .environmentObject(services.store)
            .environmentObject(services.state)
            .environmentObject(services.timer)
            .environmentObject(services.speech)
            .environmentObject(services.calendar)
            .environmentObject(services.reminders)
            .environmentObject(services.clips)
            .environmentObject(services.mcp)
            .environmentObject(services.permissions)
            .environmentObject(services.clipboard)
            .environmentObject(services.notesSync)
            .environmentObject(services.calls)
    }
}
