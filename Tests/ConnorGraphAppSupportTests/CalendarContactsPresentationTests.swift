import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Contacts Presentation Tests")
struct CalendarContactsPresentationTests {
    @Test func calendarPresentationGroupsEventsByDay() {
        let base = Date(timeIntervalSince1970: 1_000)
        let events = [
            CalendarEvent(id: CalendarEventID(rawValue: "event-1"), calendarID: CalendarID(rawValue: "work"), title: "产品讨论", start: CalendarEventDateTime(date: base), end: CalendarEventDateTime(date: base.addingTimeInterval(3_600))),
            CalendarEvent(id: CalendarEventID(rawValue: "event-2"), calendarID: CalendarID(rawValue: "work"), title: "复盘", start: CalendarEventDateTime(date: base.addingTimeInterval(86_400)), end: CalendarEventDateTime(date: base.addingTimeInterval(90_000)))
        ]

        let presentation = NativeCalendarBrowserPresentation.build(events: events, calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)

        #expect(presentation.daySections.count == 2)
        #expect(presentation.daySections.first?.events.first?.title == "产品讨论")
        #expect(presentation.eventCount == 2)
    }

    @Test func contactsPresentationBuildsRowsAndDetails() {
        let records = [
            ContactRecord(id: MailContactID(rawValue: "shiwen"), givenName: "诗闻", organizationName: "Connor", emails: [ContactEmailAddress(email: "shiwen@example.com")])
        ]

        let presentation = NativeContactsBrowserPresentation.build(records: records, query: "诗")

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].displayName == "诗闻")
        #expect(presentation.rows[0].primaryEmail == "shiwen@example.com")
        #expect(presentation.query == "诗")
    }

    @Test func accountConnectionRuntimeCreatesProviderCapabilities() async throws {
        let runtime = AccountConnectionRuntime()
        let account = runtime.makeAccount(provider: .google, displayName: "Google", primaryIdentifier: "alice@example.com")

        #expect(account.enabledCapabilities == [.mail, .calendar, .contacts])
        #expect(account.capability(.calendar)?.status == .enabled)
    }
}
