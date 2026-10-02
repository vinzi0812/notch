import SwiftUI

/// The calendar page, opened from the Calendar widget: the month to browse, and the selected day's
/// events, laid out the way the user chose in Settings (a day strip, or a month grid beside or above).
struct CalendarPage: View {
    let calendar: CalendarMonitor

    @State private var month = CalendarMonth(containing: .now)
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var events: [CalendarEvent] = []

    var body: some View {
        Group {
            if calendar.access == .granted {
                CalendarPageContent(month: $month, selected: $selected, events: events)
            } else {
                CalendarSection(calendar: calendar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Reload when the month changes, or when Calendar's data does (the monitor's refresh time moves).
        .task(id: [month.start, calendar.evaluatedAt]) {
            events = calendar.events(from: month.interval.start, to: month.interval.end)
        }
    }
}

/// The page's layout from plain values, so it can be previewed with sample events.
struct CalendarPageContent: View {
    @Binding var month: CalendarMonth
    @Binding var selected: Date
    let events: [CalendarEvent]
    @Environment(\.calendarLayout) private var layout

    private var busyDays: Set<Date> { CalendarEvent.busyDays(in: events) }
    private var dayEvents: [CalendarEvent] { CalendarEvent.events(on: selected, in: events) }

    var body: some View {
        switch layout {
        case .strip:
            VStack(spacing: 8) {
                MonthHeader(month: $month, selected: $selected)
                MonthStrip(month: month, selected: $selected, busyDays: busyDays)
                Divider().overlay(.white.opacity(0.15))
                DayEvents(day: selected, events: dayEvents)
            }
        case .beside:
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    MonthHeader(month: $month, selected: $selected, compact: true)
                    MonthGridView(month: month, selected: $selected, busyDays: busyDays, rowHeight: 19)
                }
                .frame(width: 200)
                Divider().overlay(.white.opacity(0.15))
                DayEvents(day: selected, events: dayEvents)
            }
        case .above:
            VStack(spacing: 8) {
                MonthHeader(month: $month, selected: $selected)
                MonthGridView(month: month, selected: $selected, busyDays: busyDays, rowHeight: 22)
                Divider().overlay(.white.opacity(0.15))
                DayEvents(day: selected, events: dayEvents)
            }
        }
    }
}

/// "September 2026" with Today and ‹ ›. Changing month selects its first day (or today).
private struct MonthHeader: View {
    @Binding var month: CalendarMonth
    @Binding var selected: Date
    /// Beside the events there's less room: a shorter month name.
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Text(month.start.formatted(.dateTime.month(compact ? .abbreviated : .wide).year()))
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .contentTransition(.numericText())
            Spacer()
            if !Calendar.current.isDate(selected, inSameDayAs: .now) {
                Button("Today") { show(CalendarMonth(containing: .now)) }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassControl(in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            arrow("chevron.left", months: -1)
            arrow("chevron.right", months: 1)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
    }

    private func show(_ newMonth: CalendarMonth) {
        withAnimation(.snappy) {
            month = newMonth
            selected = newMonth.defaultDay()
        }
    }

    private func arrow(_ symbol: String, months: Int) -> some View {
        Button {
            show(month.adding(months: months))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .glassControl(in: Circle())
        }
    }
}

/// The month's weeks with weekday initials: today in the accent, the selected day filled, a dot
/// under days with events.
private struct MonthGridView: View {
    let month: CalendarMonth
    @Binding var selected: Date
    let busyDays: Set<Date>
    let rowHeight: CGFloat
    @Environment(\.notchAccent) private var accent

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarMonth.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(month.weeks(), id: \.first) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        DayCell(day: day, inMonth: month.contains(day), isSelected: day == selected,
                                isBusy: busyDays.contains(day), accent: accent, height: rowHeight)
                            .onTapGesture { withAnimation(.snappy) { selected = day } }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isBusy: Bool
    let accent: Color
    let height: CGFloat

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Text(day.formatted(.dateTime.day()))
            .font(.system(size: height * 0.52, weight: isToday || isSelected ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(isSelected ? .black : isToday ? accent : .white.opacity(inMonth ? 0.9 : 0.3))
            .frame(width: height + 2, height: height)
            .background {
                if isSelected {
                    Circle().fill(isToday ? accent : .white)
                }
            }
            .overlay(alignment: .bottom) {
                if isBusy && !isSelected {
                    Circle().fill(accent.opacity(inMonth ? 1 : 0.4)).frame(width: 3, height: 3).offset(y: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

/// Every day of the month in a row that scrolls, like a week strip that runs the whole month.
private struct MonthStrip: View {
    let month: CalendarMonth
    @Binding var selected: Date
    let busyDays: Set<Date>
    @Environment(\.notchAccent) private var accent
    @Environment(\.hapticFeedbackEnabled) private var hapticEnabled
    @State private var centeredDay: Date?
    @State private var isUpdatingFromScroll = false

    var body: some View {
        GeometryReader { proxy in
            let edgePadding = max(0, (proxy.size.width - 34) / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(month.days(), id: \.self) { day in
                        let isSelected = day == selected
                        let isToday = Calendar.current.isDateInToday(day)
                        VStack(spacing: 3) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isSelected ? .black.opacity(0.6) : .white.opacity(0.4))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? .black : isToday ? accent : .white)
                            Circle()
                                .fill(busyDays.contains(day) ? (isSelected ? .black.opacity(0.6) : accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(width: 34, height: 46)
                        .background(isSelected ? (isToday ? accent : .white) : .white.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
                        .id(day)
                        .onTapGesture { withAnimation(.snappy) { selected = day } }
                    }
                }
                .padding(.horizontal, edgePadding)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $centeredDay, anchor: .center)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 18)
            }
            .onAppear {
                centeredDay = selected
            }
            .onChange(of: centeredDay) { _, newValue in
                guard let newValue, newValue != selected else { return }
                isUpdatingFromScroll = true
                selected = newValue
                if hapticEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            }
            .onChange(of: selected) { _, newValue in
                if isUpdatingFromScroll {
                    isUpdatingFromScroll = false
                    return
                }
                if centeredDay != newValue {
                    withAnimation(.snappy) {
                        centeredDay = newValue
                    }
                }
            }
        }
        .frame(height: 46)
    }
}

/// "Today · Sunday 27 September" and that day's events.
private struct DayEvents: View {
    let day: Date
    let events: [CalendarEvent]

    private var title: String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if Calendar.current.isDateInToday(day) { return "Today · \(date)" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow · \(date)" }
        return date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            if events.isEmpty {
                Text("No events")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(events) { EventRow(event: $0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One event: its calendar's color, time, title and length or place, and Join for calls.
/// Clicking it opens the event in Calendar.
struct EventRow: View {
    let event: CalendarEvent
    var compact = false
    /// Adds the weekday for events not today, for lists that span several days.
    var showsDay = false
    @Environment(\.notchAccent) private var accent

    private var color: Color {
        event.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? accent
    }

    private var time: String {
        let time = event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
        guard showsDay, !Calendar.current.isDateInToday(event.start) else { return time }
        let day = Calendar.current.isDateInTomorrow(event.start) ? "Tmrw" : event.start.formatted(.dateTime.weekday(.abbreviated))
        return event.isAllDay ? day : "\(day) \(time)"
    }

    private var detail: String? {
        if let location = event.location, !location.isEmpty, event.callURL == nil { return location }
        guard !event.isAllDay else { return nil }
        let minutes = Int(event.duration / 60)
        return minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(color).frame(width: 3)
            Text(time)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: compact ? 0 : 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !compact, let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let url = event.callURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    // Compact rows keep the room for the title: just the camera.
                    Label("Join", systemImage: "video.fill")
                        .labelStyle(CompactJoinLabelStyle(compact: compact))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, compact ? 5 : 8)
                        .padding(.vertical, 3)
                        .background(color, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Join the call")
            }
        }
        .padding(.vertical, compact ? 3 : 4)
        .padding(.horizontal, 6)
        .frame(height: compact ? 24 : 34)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { CalendarMonitor.openInCalendar(event) }
        .help("Open in Calendar")
    }
}

/// The Join label: icon and word, or just the icon in compact rows.
private struct CompactJoinLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: 4) {
                configuration.icon
                configuration.title
            }
        }
    }
}
