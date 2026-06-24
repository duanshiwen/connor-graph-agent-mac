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

    @Test func parserUnfoldsEscapedTextAndExtractsPeopleAndStatus() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:event-escaped@example.com
        SUMMARY:Long product
          review\\, roadmap\\; calendar\\nengine
        DTSTART:20260624T040000Z
        DTEND:20260624T050000Z
        STATUS:CANCELLED
        ORGANIZER;CN=诗闻:mailto:shiwen@example.com
        ATTENDEE;CN=Alice;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED:mailto:alice@example.com
        ATTENDEE;CN=Bob;ROLE=OPT-PARTICIPANT;PARTSTAT=TENTATIVE:mailto:bob@example.com
        DESCRIPTION:Line one\\nLine two
        END:VEVENT
        END:VCALENDAR
        """

        let events = try ICalendarParser().events(from: ics)

        #expect(events.count == 1)
        #expect(events[0].summary == "Long product review, roadmap; calendar\nengine")
        #expect(events[0].description == "Line one\nLine two")
        #expect(events[0].status == "CANCELLED")
        #expect(events[0].organizer?.email == "shiwen@example.com")
        #expect(events[0].organizer?.name == "诗闻")
        #expect(events[0].attendees.count == 2)
        #expect(events[0].attendees.first?.email == "alice@example.com")
        #expect(events[0].attendees.first?.participationStatus == "ACCEPTED")
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
