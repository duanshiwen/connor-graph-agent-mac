import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar CalDAV Discovery Service Tests")
struct CalendarCalDAVDiscoveryServiceTests {
    @Test func discoveryServiceDiscoversPrincipalHomeSetAndVEVENTCollections() async throws {
        let transport = SequencedCalDAVTransport(responses: [
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop><d:current-user-principal><d:href>/principal/user/</d:href></d:current-user-principal></d:prop></d:propstat></d:response></d:multistatus>
            """),
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:propstat><d:prop><c:calendar-home-set><d:href>/calendars/user/</d:href></c:calendar-home-set></d:prop></d:propstat></d:response></d:multistatus>
            """),
            CalendarCalDAVHTTPResponse(statusCode: 207, body: """
            <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
              <d:response><d:href>/calendars/user/work/</d:href><d:propstat><d:prop><d:displayname>Work</d:displayname><cs:getctag>ctag-1</cs:getctag><c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop></d:propstat></d:response>
            </d:multistatus>
            """)
        ])
        let service = CalendarCalDAVDiscoveryService(client: CalendarCalDAVHTTPClient(transport: transport))

        let result = try await service.discover(baseURL: URL(string: "https://cal.example.com")!, credential: "secret")

        #expect(result.principalURL?.absoluteString == "https://cal.example.com/principal/user/")
        #expect(result.calendarHomeSetURL?.absoluteString == "https://cal.example.com/calendars/user/")
        #expect(result.collections.map(\.displayName) == ["Work"])
        #expect(transport.requests.map(\.method) == ["PROPFIND", "PROPFIND", "PROPFIND"])
    }
}

private final class SequencedCalDAVTransport: CalendarCalDAVHTTPTransport, @unchecked Sendable {
    private var responses: [CalendarCalDAVHTTPResponse]
    var requests: [CalendarCalDAVHTTPRequest] = []

    init(responses: [CalendarCalDAVHTTPResponse]) { self.responses = responses }

    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}
