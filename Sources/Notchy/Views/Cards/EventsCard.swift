import SwiftUI

/// Read-only view of the user's calendars. There are intentionally no create/edit/delete actions.
struct EventsCard: View {
    var expanded = false

    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        Card(tint: DS.Palette.events) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(title: "Events", symbol: "calendar")
                    Spacer(minLength: 0)
                    Menu {
                        Button("Refresh") { calendar.refresh() }
                        Button("Open Calendar") { calendar.openCalendarApp() }
                        Divider()
                        DashboardMenuItems(tool: .calendar)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Calendar options")
                }

                if calendar.hasAccess {
                    if expanded { weekColumns } else { todayList }
                } else {
                    accessPrompt
                }

                Spacer(minLength: 0)
                footer
            }
        }
    }

    private var todayList: some View {
        let today = Date()
        let todays = calendar.events(on: today).filter { $0.end > today || $0.isAllDay }
        let upcoming = calendar.events.filter { !Calendar.current.isDateInToday($0.start) && $0.start > today }.prefix(4)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("TODAY", trailing: today.formatted(.dateTime.weekday(.abbreviated).day()))
                ForEach(todays) { EventRow(event: $0) }
                if todays.isEmpty {
                    Text("Nothing else today")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkTertiary)
                }
                if !upcoming.isEmpty {
                    sectionHeader("UPCOMING", trailing: nil).padding(.top, 4)
                    ForEach(Array(upcoming)) { EventRow(event: $0, showsDay: true) }
                }
            }
        }
    }

    private var weekColumns: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader(DateText.relativeDay(day).uppercased(), trailing: day.formatted(.dateTime.day()))
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                let items = calendar.events(on: day)
                                ForEach(items) { EventRow(event: $0) }
                                if items.isEmpty {
                                    Text("Free").font(.system(size: 11)).foregroundStyle(DS.inkTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(width: 150)
                }
            }
        }
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(calendar.isDenied
                 ? "Calendar access is turned off. Allow it in System Settings to see your events here."
                 : "See today's events right in the notch. HappyNotch only reads your calendars.")
                .font(.system(size: 11.5))
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(calendar.isDenied ? "Open Settings" : "Connect Calendar") {
                if calendar.isDenied { calendar.openPrivacySettings() } else { calendar.requestAccess() }
            }
            .buttonStyle(InkCapsuleButtonStyle())
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: calendar.hasAccess ? "checkmark.circle" : "circle.dashed")
            Text(calendar.hasAccess ? "Connected · read-only" : "Not connected")
            Spacer(minLength: 0)
            if calendar.hasAccess {
                InkIconButton(symbol: "arrow.clockwise", label: "Refresh events", size: 20) { calendar.refresh() }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(DS.inkSecondary)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).fontWeight(.bold)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.system(size: 10))
        .foregroundStyle(DS.inkSecondary)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    var showsDay = false

    private var isNow: Bool { event.start <= Date() && event.end > Date() && !event.isAllDay }

    private var timeText: String {
        if event.isAllDay { return showsDay ? "\(DateText.relativeDay(event.start)) · All day" : "All day" }
        let range = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        return showsDay ? "\(DateText.relativeDay(event.start)) · \(event.start.formatted(date: .omitted, time: .shortened))" : range
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(isNow ? "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" : timeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Circle()
                .strokeBorder(event.color, lineWidth: 1.6)
                .background(Circle().fill(isNow ? event.color : .clear))
                .frame(width: 13, height: 13)
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isNow ? 0.6 : 0.35)))
        .opacity(event.end < Date() && !event.isAllDay ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeText), \(event.calendarTitle) calendar")
    }
}
