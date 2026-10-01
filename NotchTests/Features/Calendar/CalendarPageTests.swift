import CoreGraphics
import Foundation
import Testing
@testable import Notch

@MainActor
struct CallLinkTests {
    @Test(arguments: [
        "https://meet.google.com/abc-defg-hij",
        "https://us02web.zoom.us/j/123456789?pwd=abc",
        "https://teams.microsoft.com/l/meetup-join/19%3ameeting",
        "https://facetime.apple.com/join#v=1&p=abc",
        "https://acme.webex.com/meet/someone",
    ])
    func findsCallLinks(link: String) {
        #expect(CallLink.find(in: ["Join here: \(link) thanks"]) == URL(string: link))
    }

    @Test func ignoresOtherLinksAndLookalikes() {
        #expect(CallLink.find(in: ["Agenda: https://docs.google.com/document/d/1", "https://notzoom.us/j/1"]) == nil)
    }

    @Test func checksEachPlaceInOrder() {
        let url = CallLink.find(in: [nil, "Room 4B", "Notes: https://zoom.us/j/42"])
        #expect(url == URL(string: "https://zoom.us/j/42"))
    }
}

@MainActor
struct CalendarMonthTests {
    let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func aMonthHasItsDays() {
        #expect(CalendarMonth(containing: date(2026, 9, 27), calendar: calendar).days(calendar: calendar).count == 30)
        #expect(CalendarMonth(containing: date(2028, 2, 10), calendar: calendar).days(calendar: calendar).count == 29, "leap year")
    }

    @Test func movingAcrossTheYear() {
        let december = CalendarMonth(containing: date(2026, 12, 5), calendar: calendar)
        #expect(december.adding(months: 1, calendar: calendar).start == date(2027, 1, 1))
    }

    @Test func arrivingAtAMonthSelectsTodayOrTheFirst() {
        let today = date(2026, 9, 27, 15)
        let september = CalendarMonth(containing: today, calendar: calendar)
        #expect(september.defaultDay(today: today, calendar: calendar) == date(2026, 9, 27))
        #expect(september.adding(months: 1, calendar: calendar).defaultDay(today: today, calendar: calendar) == date(2026, 10, 1))
    }

    private func event(_ id: String, from start: Date, to end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    @Test func aDaysEventsPutAllDayFirst() {
        let events = [
            event("late", from: date(2026, 9, 27, 18), to: date(2026, 9, 27, 19)),
            event("early", from: date(2026, 9, 27, 9), to: date(2026, 9, 27, 10)),
            event("birthday", from: date(2026, 9, 27), to: date(2026, 9, 28), allDay: true),
            event("tomorrow", from: date(2026, 9, 28, 9), to: date(2026, 9, 28, 10)),
        ]
        #expect(CalendarEvent.events(on: date(2026, 9, 27), in: events, calendar: calendar).map(\.id) == ["birthday", "early", "late"])
    }

    @Test func aMultiDayEventIsOnEachDayItCovers() {
        let trip = event("trip", from: date(2026, 9, 10, 12), to: date(2026, 9, 12, 12))
        #expect(CalendarEvent.busyDays(in: [trip], calendar: calendar) == [date(2026, 9, 10), date(2026, 9, 11), date(2026, 9, 12)])
        #expect(CalendarEvent.events(on: date(2026, 9, 11), in: [trip], calendar: calendar).map(\.id) == ["trip"])
    }

    @Test func anAllDayEventEndsAtMidnight() {
        let holiday = event("holiday", from: date(2026, 9, 29), to: date(2026, 9, 30), allDay: true)
        #expect(CalendarEvent.busyDays(in: [holiday], calendar: calendar) == [date(2026, 9, 29)])
    }
}

@MainActor
struct CalendarWidgetTests {
    @Test func startWording() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 9))!
        func at(_ day: Int, _ hour: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }
        let meeting = CalendarEvent(id: "m", title: "m", start: at(27, 10), end: at(27, 11), isAllDay: false)
        let ongoing = CalendarEvent(id: "o", title: "o", start: at(27, 8), end: at(27, 10), isAllDay: false)
        let tomorrow = CalendarEvent(id: "t", title: "t", start: at(28, 0), end: at(29, 0), isAllDay: true)

        #expect(StartLabel.text(for: meeting, at: now) == meeting.start.formatted(date: .omitted, time: .shortened))
        #expect(StartLabel.text(for: ongoing, at: now) == "Now")
        #expect(StartLabel.text(for: tomorrow, at: now) == "Tomorrow · All day")
    }

    @Test func calendarOpensItsOwnTallPage() {
        let model = NotchViewModel(geometry: .previewHardware, settings: .ephemeral())
        #expect(model.calendar.tab?.style == .page)
        model.expand()
        model.select(tab: model.calendar)
        #expect(model.isTall)
    }
}

@MainActor
struct CalendarLayoutTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func weeksAreWholeAndStartOnTheUsersFirstWeekday() {
        let sundays = calendar(firstWeekday: 1)
        let september = CalendarMonth(containing: date(2026, 9, 15, in: sundays), calendar: sundays)
        let weeks = september.weeks(calendar: sundays)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.count == 5)
        #expect(weeks.first?.first == date(2026, 8, 30, in: sundays), "1 September 2026 is a Tuesday")
        #expect(weeks.last?.last == date(2026, 10, 3, in: sundays))

        let mondays = calendar(firstWeekday: 2)
        #expect(september.weeks(calendar: mondays).first?.first == date(2026, 8, 31, in: mondays))
    }

    @Test func everyDayOfTheMonthIsInTheGrid() {
        let gregorian = calendar(firstWeekday: 1)
        let month = CalendarMonth(containing: date(2027, 2, 10, in: gregorian), calendar: gregorian)
        let gridDays = Set(month.weeks(calendar: gregorian).flatMap { $0 })
        #expect(month.days(calendar: gregorian).allSatisfy(gridDays.contains))
    }

    @Test func weekdayInitialsFollowTheFirstWeekday() {
        #expect(CalendarMonth.weekdaySymbols(calendar: calendar(firstWeekday: 1)).first == "S")
        #expect(CalendarMonth.weekdaySymbols(calendar: calendar(firstWeekday: 2)) == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test func theLayoutIsSavedAndResizesThePanel() {
        let suite = "CalendarLayoutTests.\(UUID().uuidString)"
        let settings = NotchSettings(defaults: UserDefaults(suiteName: suite)!)
        #expect(settings.calendarLayout == .strip)
        var geometryChanges = 0
        settings.onGeometryChanged = { geometryChanges += 1 }
        settings.calendarLayout = .above
        #expect(geometryChanges == 1, "month above needs a taller panel")
        #expect(NotchSettings(defaults: UserDefaults(suiteName: suite)!).calendarLayout == .above)
        settings.resetCalendar()
        #expect(settings.calendarLayout == .strip)
    }

    @Test func thePanelGrowsOnlyForTheTallLayout() {
        var geometry = NotchGeometry.previewHardware
        let usual = geometry.panelSize.height
        geometry.extraPageHeight = NotchGeometry.calendarMonthAboveExtra
        #expect(geometry.panelSize.height == usual + NotchGeometry.calendarMonthAboveExtra)
        #expect(geometry.panelRect.contains(geometry.expandedRect(height: geometry.tallHeight + NotchGeometry.calendarMonthAboveExtra)))
    }
}
