import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("CalDAV Calendar Mutation Adapter Tests")
struct CalDAVCalendarMutationAdapterTests {
    @Test func createsWithIfNoneMatchAndVerifiesRemoteEvent() async throws {
        let transport = QueueCalDAVTransport(responses: [
            .init(statusCode: 201, body: "", headers: ["ETag": "\"v1\""]),
            .init(statusCode: 200, body: Self.ics(uid: "uid-1", title: "Focus"), headers: ["ETag": "\"v1\""])
        ])
        let adapter = CalDAVCalendarMutationAdapter(client: .init(transport: transport), credentialProvider: { _ in "secret" }, uidGenerator: { "uid-1" }, resourceNameGenerator: { "resource-1.ics" })
        let account = Self.account
        let collection = Self.collection
        let request = CalendarMutationRequest(operation: .create, draft: .init(calendarID: collection.id, title: "Focus", start: .init(date: Date(timeIntervalSince1970: 1_782_276_400)), end: .init(date: Date(timeIntervalSince1970: 1_782_280_000))))
        let result = try await adapter.mutate(request, account: account, collection: collection, currentEvent: nil)
        let requests = await transport.recordedRequests()
        #expect(requests.first?.method == "PUT")
        #expect(requests.first?.headers["If-None-Match"] == "*")
        #expect(requests.last?.method == "GET")
        #expect(result.remoteVersion?.value == "\"v1\"")
        #expect(result.confirmedEvent?.title == "Focus")
    }

    @Test func updatePreservesWeakETagExactly() async throws {
        let weakETag = "W/\"opaque-v7\""
        let transport = QueueCalDAVTransport(responses: [
            .init(statusCode: 200, body: Self.ics(uid: "uid-1", title: "Remote"), headers: ["ETag": weakETag]),
            .init(statusCode: 204, body: "", headers: ["ETag": weakETag]),
            .init(statusCode: 200, body: Self.ics(uid: "uid-1", title: "Updated"), headers: ["ETag": weakETag])
        ])
        let adapter = CalDAVCalendarMutationAdapter(client: .init(transport: transport), credentialProvider: { _ in nil })
        let event = CalendarEvent(id: .init(rawValue: "caldav-c-uid-1"), calendarID: Self.collection.id, title: "Remote", start: .init(date: Date(timeIntervalSince1970: 1_782_276_400)), end: .init(date: Date(timeIntervalSince1970: 1_782_280_000)), sourceMetadata: .init(sourceKind: .genericCalDAV, remoteIdentifier: "uid-1", resourceURL: URL(string: "https://cal.example.com/cal/work/e.ics"), etag: weakETag))
        let result = try await adapter.mutate(.init(operation: .update, eventID: event.id, expectedVersion: .init(value: weakETag), patch: .init(title: .set("Updated"))), account: Self.account, collection: Self.collection, currentEvent: event)
        let requests = await transport.recordedRequests()
        #expect(requests[1].headers["If-Match"] == weakETag)
        #expect(result.remoteVersion?.value == weakETag)
        #expect(result.confirmedEvent?.id == event.id)
    }

    @Test func updateRejectsStaleRemoteETagWithoutPut() async throws {
        let transport = QueueCalDAVTransport(responses: [.init(statusCode: 200, body: Self.ics(uid: "uid-1", title: "Remote"), headers: ["ETag": "\"v2\""])])
        let adapter = CalDAVCalendarMutationAdapter(client: .init(transport: transport), credentialProvider: { _ in nil })
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: Self.collection.id, title: "Old", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)), sourceMetadata: .init(sourceKind: .genericCalDAV, remoteIdentifier: "uid-1", resourceURL: URL(string: "https://cal.example.com/cal/work/e.ics"), etag: "\"v1\""))
        await #expect(throws: CalendarMutationError.self) {
            try await adapter.mutate(.init(operation: .update, eventID: event.id, expectedVersion: .init(value: "\"v1\""), patch: .init(title: .set("New"))), account: Self.account, collection: Self.collection, currentEvent: event)
        }
        #expect(await transport.recordedRequests().count == 1)
    }

    private static var account: CalendarAccount { CalendarAccount(id: .init(rawValue: "a"), provider: .genericCalDAVCardDAV, sourceKind: .genericCalDAV, displayName: "Cal", configuration: .init(sourceKind: .genericCalDAV, authMode: .appPassword, syncMode: .bidirectional, calendarHomeSetURL: URL(string: "https://cal.example.com/cal/"), providerMetadata: ["collectionURL:c": "https://cal.example.com/cal/work/"])) }
    private static var collection: CalendarCollection { CalendarCollection(id: .init(rawValue: "c"), accountID: .init(rawValue: "a"), displayName: "Work") }
    private static func ics(uid: String, title: String) -> String { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:\(uid)\r\nSUMMARY:\(title)\r\nDTSTART:20260624T040000Z\r\nDTEND:20260624T050000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n" }
}

private actor QueueCalDAVTransport: CalendarCalDAVHTTPTransport {
    var responses: [CalendarCalDAVHTTPResponse]
    var requests: [CalendarCalDAVHTTPRequest] = []
    init(responses: [CalendarCalDAVHTTPResponse]) { self.responses = responses }
    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse { requests.append(request); return responses.removeFirst() }
    func recordedRequests() -> [CalendarCalDAVHTTPRequest] { requests }
}
