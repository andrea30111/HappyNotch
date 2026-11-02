import AppKit
import Combine
import EventKit
import SwiftUI

@MainActor
final class EventStoreProvider {
    static let shared = EventStoreProvider()
    let store = EKEventStore()
}

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let location: String?
    let color: Color

    init(_ event: EKEvent) {
        id = (event.eventIdentifier ?? UUID().uuidString) + "@\(event.startDate.timeIntervalSince1970)"
        title = event.title ?? "Untitled event"
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        calendarTitle = event.calendar?.title ?? ""
        location = event.location
        if let cg = event.calendar?.cgColor, let ns = NSColor(cgColor: cg) {
            color = Color(nsColor: ns)
        } else {
            color = .blue
        }
    }
}

/// Read-only access to Apple Calendar via EventKit.
/// This type deliberately never creates, edits or deletes events.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorization: EKAuthorizationStatus
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var lastRefresh: Date?

    private var cancellables = Set<AnyCancellable>()
    private var ek: EKEventStore { EventStoreProvider.shared.store }

    init() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    var hasAccess: Bool { authorization == .fullAccess }
    var isDenied: Bool { authorization == .denied || authorization == .restricted || authorization == .writeOnly }

    func requestAccess() {
        Task {
            _ = try? await ek.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            refresh()
        }
    }

    func refresh() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        events = hasAccess ? fetch(from: start, to: end) : []
        lastRefresh = Date()
    }

    func fetch(from start: Date, to end: Date) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let predicate = ek.predicateForEvents(withStart: start, end: end, calendars: nil)
        return ek.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarEvent.init)
    }

    func events(on day: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day) }
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
