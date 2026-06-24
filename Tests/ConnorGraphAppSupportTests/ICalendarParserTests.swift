import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("iCalendar Parser Tests")
struct ICalendarParserTests {
    @Test func parserExtractsSingleVEVENTWithDateTimeAndMetadata() throws {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Connor//Calendar Tests//EN
        BEGIN:VEVENT
        UID:event-1@example.com
        SUMMARY:产品讨论
        DTSTART;TZID=Asia/Shanghai:20260624T140000
        DTEND;TZID=Asia/Shanghai:20260624T150000
        LOCATION:杭州
        DESCRIPTION:讨论 Calendar Source Platform
        URL:https://example.com/meet
        LAST-MODIFIED:20260624T030000Z
        END:VEVENT
        END:VCALENDAR
        """

        let events = try ICalendarParser().events(from: ics)

        #expect(events.count == 1)
        #expect(events[0].uid == "event-1@example.com")
        #expect(events[0].summary == "产品讨论")
        #expect(events[0].start.timeZoneIdentifier == "Asia/Shanghai")
        #expect(events[0].end?.timeZoneIdentifier == "Asia/Shanghai")
        #expect(events[0].location == "杭州")
        #expect(events[0].description == "讨论 Calendar Source Platform")
        #expect(events[0].url?.absoluteString == "https://example.com/meet")
        #expect(events[0].lastModified != nil)
    }

    @Test func parserExtractsAllDayEventAndRecurrenceSummary() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:event-2@example.com
        SUMMARY:每周复盘
        DTSTART;VALUE=DATE:20260625
        DTEND;VALUE=DATE:20260626
        RRULE:FREQ=WEEKLY;COUNT=5
        END:VEVENT
        END:VCALENDAR
        """

        let events = try ICalendarParser().events(from: ics)

        #expect(events.count == 1)
        #expect(events[0].isAllDay)
        #expect(events[0].recurrenceRule == "FREQ=WEEKLY;COUNT=5")
    }
}
