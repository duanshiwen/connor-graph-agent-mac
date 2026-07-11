import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Calendar CalDAV HTTP Client Tests")
struct CalendarCalDAVHTTPClientTests {
    @Test func propfindBuildsDepthAndAuthorizationHeadersAndRedactsDiagnostics() async throws {
        let transport = RecordingCalDAVTransport(response: CalendarCalDAVHTTPResponse(statusCode: 207, body: "<multistatus />", headers: [:]))
        let client = CalendarCalDAVHTTPClient(transport: transport)

        let response = try await client.propfind(url: URL(string: "https://cal.example.com/dav")!, depth: "1", body: "<propfind />", credential: "secret-token")

        #expect(response.statusCode == 207)
        #expect(transport.lastRequest?.method == "PROPFIND")
        #expect(transport.lastRequest?.headers["Depth"] == "1")
        #expect(transport.lastRequest?.headers["Authorization"] == "Bearer secret-token")
        #expect(!transport.lastRequest!.redactedDescription.contains("secret-token"))
        #expect(transport.lastRequest!.redactedDescription.contains("<redacted>"))
    }

    @Test func putAndDeleteUseOptimisticConcurrencyHeaders() async throws {
        let transport = RecordingCalDAVTransport(response: CalendarCalDAVHTTPResponse(statusCode: 204, body: "", headers: ["ETag": "\"v2\""]))
        let client = CalendarCalDAVHTTPClient(transport: transport)
        _ = try await client.put(url: URL(string: "https://cal.example.com/c/e.ics")!, body: "BEGIN:VCALENDAR", credential: "secret", ifMatch: "\"v1\"")
        #expect(transport.lastRequest?.method == "PUT")
        #expect(transport.lastRequest?.headers["If-Match"] == "\"v1\"")
        #expect(transport.lastRequest?.headers["Content-Type"] == "text/calendar; charset=utf-8")
        _ = try await client.delete(url: URL(string: "https://cal.example.com/c/e.ics")!, credential: "secret", ifMatch: "\"v2\"")
        #expect(transport.lastRequest?.method == "DELETE")
        #expect(transport.lastRequest?.headers["If-Match"] == "\"v2\"")
    }

    @Test func createUsesIfNoneMatchAndPreconditionFailureMapsConflict() async throws {
        let transport = RecordingCalDAVTransport(response: CalendarCalDAVHTTPResponse(statusCode: 412, body: "Precondition Failed"))
        let client = CalendarCalDAVHTTPClient(transport: transport)
        await #expect(throws: CalendarCalDAVHTTPError.conflict) {
            try await client.put(url: URL(string: "https://cal.example.com/c/new.ics")!, body: "ics", credential: nil, ifNoneMatch: "*")
        }
        #expect(transport.lastRequest?.headers["If-None-Match"] == "*")
    }

    @Test func reportMapsUnauthorizedToTypedError() async throws {
        let transport = RecordingCalDAVTransport(response: CalendarCalDAVHTTPResponse(statusCode: 401, body: "Unauthorized", headers: [:]))
        let client = CalendarCalDAVHTTPClient(transport: transport)

        var unauthorized = false
        do {
            _ = try await client.report(url: URL(string: "https://cal.example.com/calendar")!, depth: "1", body: "<calendar-query />", credential: "secret-token")
        } catch CalendarCalDAVHTTPError.unauthorized {
            unauthorized = true
        }

        #expect(unauthorized)
        #expect(transport.lastRequest?.method == "REPORT")
    }
}

private final class RecordingCalDAVTransport: CalendarCalDAVHTTPTransport, @unchecked Sendable {
    var lastRequest: CalendarCalDAVHTTPRequest?
    let response: CalendarCalDAVHTTPResponse

    init(response: CalendarCalDAVHTTPResponse) {
        self.response = response
    }

    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse {
        lastRequest = request
        return response
    }
}
