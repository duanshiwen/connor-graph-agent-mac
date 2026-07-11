import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Mutation Service Tests")
struct CalendarMutationServiceTests {
    @Test func routesApprovedMutationAndPersistsConfirmedEventAndAudit() async throws {
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: temporaryURL())
        let account = CalendarAccount(id: .init(rawValue: "a"), provider: .genericCalDAVCardDAV, sourceKind: .genericCalDAV, displayName: "CalDAV", configuration: .init(sourceKind: .genericCalDAV, authMode: .appPassword, syncMode: .bidirectional))
        let collection = CalendarCollection(id: .init(rawValue: "c"), accountID: account.id, displayName: "Work")
        try await store.saveSnapshot(.init(accounts: [account], collections: [collection]))
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: collection.id, title: "Created", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)), updatedAt: Date(timeIntervalSince1970: 30))
        let result = CalendarMutationResult(receipt: .init(mutationKind: .createEvent, eventID: event.id, approved: true, summary: "Created"), confirmedEvent: event, remoteVersion: .init(value: "v1"))
        let adapter = StubCalendarMutationAdapter(result: result)
        let service = CalendarMutationService(store: store, adapters: [.genericCalDAV: adapter])
        let request = CalendarMutationRequest(operation: .create, draft: .init(calendarID: collection.id, title: "Created", start: event.start, end: event.end), runID: "run", sessionID: "session")
        _ = try await service.mutate(request)
        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.events == [event])
        #expect(snapshot.mutationAudits.count == 1)
        #expect(snapshot.mutationAudits[0].status == .confirmed)
    }

    @Test func rejectsUnknownCalendarIDWithoutMutationAudit() async throws {
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: temporaryURL())
        let account = CalendarAccount(id: .init(rawValue: "a"), provider: .genericCalDAVCardDAV, sourceKind: .genericCalDAV, displayName: "CalDAV", configuration: .init(sourceKind: .genericCalDAV, authMode: .appPassword, syncMode: .bidirectional))
        let collection = CalendarCollection(id: .init(rawValue: "calendar-real-id"), accountID: account.id, displayName: "Work")
        try await store.saveSnapshot(.init(accounts: [account], collections: [collection]))
        let service = CalendarMutationService(store: store, adapters: [.genericCalDAV: StubCalendarMutationAdapter(result: nil)])
        let unknownID = CalendarID(rawValue: "default")

        await #expect(throws: CalendarMutationError.calendarNotFound(unknownID)) {
            try await service.mutate(.init(operation: .create, draft: .init(calendarID: unknownID, title: "x", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)))))
        }
        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.events.isEmpty)
        #expect(snapshot.mutationAudits.isEmpty)
    }

    @Test func rejectsReadOnlyAccountBeforeAdapterCall() async throws {
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: temporaryURL())
        let account = CalendarAccount(id: .init(rawValue: "a"), provider: .genericCalDAVCardDAV, sourceKind: .genericCalDAV, displayName: "CalDAV")
        let collection = CalendarCollection(id: .init(rawValue: "c"), accountID: account.id, displayName: "Work")
        try await store.saveSnapshot(.init(accounts: [account], collections: [collection]))
        let service = CalendarMutationService(store: store, adapters: [.genericCalDAV: StubCalendarMutationAdapter(result: nil)])
        await #expect(throws: CalendarMutationError.readOnlySource) {
            try await service.mutate(.init(operation: .create, draft: .init(calendarID: collection.id, title: "x", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)))))
        }
    }

    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("calendar-mutation-\(UUID().uuidString).json") }
}

private actor StubCalendarMutationAdapter: CalendarMutationAdapter {
    let result: CalendarMutationResult?
    init(result: CalendarMutationResult?) { self.result = result }
    func mutate(_ request: CalendarMutationRequest, account: CalendarAccount, collection: CalendarCollection?, currentEvent: CalendarEvent?) async throws -> CalendarMutationResult {
        guard let result else { throw CalendarMutationError.remoteFailure("unexpected") }
        return result
    }
}
