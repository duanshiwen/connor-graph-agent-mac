import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar CalDAV Event Fetcher Tests")
struct CalendarCalDAVEventFetcherTests {
    @Test func fetcherMapsCalendarQueryMultistatusToCalendarEvents() async throws {
        let body = """
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response><d:href>/cal/work/event-1.ics</d:href><d:propstat><d:prop><d:getetag>etag-1</d:getetag><c:calendar-data><![CDATA[BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:event-1
        SUMMARY:CalDAV Meeting
        DTSTART:20260624T040000Z
        DTEND:20260624T050000Z
        END:VEVENT
        END:VCALENDAR]]></c:calendar-data></d:prop></d:propstat></d:response>
        </d:multistatus>
        """
        let transport = SingleCalDAVTransport(response: CalendarCalDAVHTTPResponse(statusCode: 207, body: body))
        let fetcher = CalendarCalDAVEventFetcher(client: CalendarCalDAVHTTPClient(transport: transport))
        let collection = CalendarCollection(id: CalendarID(rawValue: "calendar-work"), accountID: CalendarAccountID(rawValue: "account"), displayName: "Work", isReadOnly: true)

        let events = try await fetcher.fetchEvents(collection: collection, collectionURL: URL(string: "https://cal.example.com/cal/work/")!, credential: "secret", windowStart: Date(timeIntervalSince1970: 1), windowEnd: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(events.count == 1)
        #expect(events[0].title == "CalDAV Meeting")
        #expect(events[0].calendarID == collection.id)
        #expect(events[0].sourceMetadata?.remoteIdentifier == "event-1")
        #expect(events[0].sourceMetadata?.etag == "etag-1")
        #expect(events[0].sourceMetadata?.resourceURL == URL(string: "https://cal.example.com/cal/work/event-1.ics"))
        #expect(transport.lastRequest?.method == "REPORT")
        #expect(transport.lastRequest?.body.contains("calendar-query") == true)
    }
}

private final class SingleCalDAVTransport: CalendarCalDAVHTTPTransport, @unchecked Sendable {
    let response: CalendarCalDAVHTTPResponse
    var lastRequest: CalendarCalDAVHTTPRequest?
    init(response: CalendarCalDAVHTTPResponse) { self.response = response }
    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse { lastRequest = request; return response }
}
