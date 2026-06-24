import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar CalDAV Connector Tests")
struct CalendarCalDAVConnectorTests {
    @Test func connectorCanBeRegisteredForProviderSpecificCalDAVKinds() {
        let connector = CalendarCalDAVConnector(kind: .appleICloudCalDAV)
        #expect(connector.kind == .appleICloudCalDAV)
    }

    @Test func connectorDiscoversCollectionsAndFetchesEventsReadOnly() async throws {
        let responses = [
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop><d:current-user-principal><d:href>/principal/user/</d:href></d:current-user-principal></d:prop></d:propstat></d:response></d:multistatus>
            """),
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:propstat><d:prop><c:calendar-home-set><d:href>/calendars/user/</d:href></c:calendar-home-set></d:prop></d:propstat></d:response></d:multistatus>
            """),
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/calendars/user/work/</d:href><d:propstat><d:prop><d:displayname>Work</d:displayname><c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop></d:propstat></d:response></d:multistatus>
            """),
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/calendars/user/work/event.ics</d:href><d:propstat><d:prop><d:getetag>etag</d:getetag><c:calendar-data><![CDATA[BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:caldav-event
            SUMMARY:CalDAV synced event
            DTSTART:20260624T040000Z
            DTEND:20260624T050000Z
            END:VEVENT
            END:VCALENDAR]]></c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>
            """)
        ]
        let transport = ConnectorSequenceTransport(responses: responses)
        let client = CalendarCalDAVHTTPClient(transport: transport)
        let connector = CalendarCalDAVConnector(
            discoveryService: CalendarCalDAVDiscoveryService(client: client),
            eventFetcher: CalendarCalDAVEventFetcher(client: client),
            now: { Date(timeIntervalSince1970: 1_782_278_400) }
        )
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-caldav"),
            provider: .genericCalDAVCardDAV,
            sourceKind: .genericCalDAV,
            displayName: "CalDAV",
            configuration: CalendarSourceConfiguration(sourceKind: .genericCalDAV, authMode: .appPassword, serverURL: URL(string: "https://cal.example.com"))
        )

        let result = try await connector.sync(request: CalendarSourceSyncRequest(account: account, credential: "secret", runID: "run-caldav"))

        #expect(result.updatedCollections == 1)
        #expect(result.insertedEvents == 1)
        #expect(result.collections.first?.isReadOnly == true)
        #expect(result.events.first?.title == "CalDAV synced event")
    }
}

private final class ConnectorSequenceTransport: CalendarCalDAVHTTPTransport, @unchecked Sendable {
    private var responses: [CalendarCalDAVHTTPResponse]
    init(responses: [CalendarCalDAVHTTPResponse]) { self.responses = responses }
    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse { responses.removeFirst() }
}
