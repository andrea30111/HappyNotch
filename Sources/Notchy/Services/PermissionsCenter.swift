import AppKit
import AVFoundation
import EventKit
import Speech

@MainActor
final class PermissionsCenter: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case calendar, microphone, speech, screenRecording, reminders
        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "Calendar"
            case .microphone: return "Microphone"
            case .speech: return "Speech Recognition"
            case .screenRecording: return "Screen Recording"
            case .reminders: return "Reminders"
            }
        }

        var reason: String {
            switch self {
            case .calendar: return "Show today's events in the notch. Read-only."
            case .microphone: return "Dictate tasks and notes, and record your side of a call."
            case .speech: return "Turn your voice into text, on-device."
            case .screenRecording: return "Capture Clips, and record Teams audio during a call you are on."
            case .reminders: return "Optional. Only used if you turn on Reminders sync."
            }
        }

        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .microphone: return "mic.fill"
            case .speech: return "waveform"
            case .screenRecording: return "camera.viewfinder"
            case .reminders: return "checklist"
            }
        }

        var settingsAnchor: String {
            switch self {
            case .calendar: return "Privacy_Calendars"
            case .microphone: return "Privacy_Microphone"
            case .speech: return "Privacy_SpeechRecognition"
            case .screenRecording: return "Privacy_ScreenCapture"
            case .reminders: return "Privacy_Reminders"
            }
        }
    }

    enum Status { case notDetermined, granted, denied }

    @Published private(set) var statuses: [Kind: Status] = [:]

    private let calendar: CalendarService
    private let reminders: RemindersSync
    private var screenRecordingRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "screenRecordingRequested") }
        set { UserDefaults.standard.set(newValue, forKey: "screenRecordingRequested") }
    }

    init(calendar: CalendarService, reminders: RemindersSync) {
        self.calendar = calendar
        self.reminders = reminders
        refresh()
    }

    var requiredGranted: Bool {
        [Kind.calendar, .microphone, .speech, .screenRecording].allSatisfy { statuses[$0] == .granted }
    }

    func status(_ kind: Kind) -> Status { statuses[kind] ?? .notDetermined }

    func refresh() {
        var next: [Kind: Status] = [:]
        next[.calendar] = Self.map(EKEventStore.authorizationStatus(for: .event))
        next[.reminders] = Self.map(EKEventStore.authorizationStatus(for: .reminder))
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: next[.microphone] = .granted
        case .notDetermined: next[.microphone] = .notDetermined
        default: next[.microphone] = .denied
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: next[.speech] = .granted
        case .notDetermined: next[.speech] = .notDetermined
        default: next[.speech] = .denied
        }
        next[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : (screenRecordingRequested ? .denied : .notDetermined)
        if next != statuses { statuses = next }
    }

    func request(_ kind: Kind) {
        if status(kind) == .denied {
            openSettings(kind)
            return
        }
        switch kind {
        case .calendar:
            calendar.requestAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
        case .reminders:
            reminders.requestAccess { [weak self] in self?.refresh() }
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        case .screenRecording:
            screenRecordingRequested = true
            if !CGRequestScreenCaptureAccess() { openSettings(kind) }
            refresh()
        }
    }

    func openSettings(_ kind: Kind) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> Status {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}
