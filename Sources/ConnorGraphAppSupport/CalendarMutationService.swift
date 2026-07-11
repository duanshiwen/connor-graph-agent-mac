import Foundation
import ConnorGraphCore

public protocol CalendarMutationAdapter: Sendable {
    func mutate(_ request: CalendarMutationRequest, account: CalendarAccount, collection: CalendarCollection?, currentEvent: CalendarEvent?) async throws -> CalendarMutationResult
}

public struct CalendarMutationService: Sendable {
    private let store: FileBackedCalendarSourceRuntimeStore
    private let adapters: [CalendarSourceKind: any CalendarMutationAdapter]

    public init(store: FileBackedCalendarSourceRuntimeStore, adapters: [CalendarSourceKind: any CalendarMutationAdapter]) { self.store = store; self.adapters = adapters }

    public func mutate(_ input: CalendarMutationRequest) async throws -> CalendarMutationResult {
        let request = try input.validated()
        let snapshot = try await store.loadSnapshot()
        let current: CalendarEvent?
        if let eventID = request.eventID {
            guard let event = snapshot.events.first(where: { $0.id == eventID }) else { throw CalendarMutationError.eventNotFound }
            current = event
        } else {
            current = nil
        }
        guard let calendarID = request.draft?.calendarID ?? current?.calendarID else { throw CalendarMutationError.eventNotFound }
        guard let collection = snapshot.collections.first(where: { $0.id == calendarID }) else { throw CalendarMutationError.calendarNotFound(calendarID) }
        guard let account = snapshot.accounts.first(where: { $0.id == collection.accountID }) else { throw CalendarMutationError.accountNotFound(collection.accountID) }
        guard account.configuration.syncMode == .bidirectional, account.sourceKind.supportsWrite else { throw CalendarMutationError.readOnlySource }
        guard !collection.isReadOnly else { throw CalendarMutationError.readOnlyCollection(collection.capabilities.readOnlyReason) }
        if current?.sourceMetadata?.isRecurring == true || current?.recurrenceSummary != nil { throw CalendarMutationError.recurrenceUnsupported }
        if current?.sourceMetadata?.hasAttendees == true || !(current?.attendees.isEmpty ?? true) || current?.sourceMetadata?.organizerEmail != nil || current?.sourceMetadata?.scheduleTag != nil { throw CalendarMutationError.schedulingUnsupported }
        guard let adapter = adapters[account.sourceKind] else { throw CalendarMutationError.remoteFailure("No mutation adapter for source") }
        let result = try await adapter.mutate(request, account: account, collection: collection, currentEvent: current)
        let audit = CalendarMutationAuditRecord(runID: request.runID, sessionID: request.sessionID, accountID: account.id, calendarID: calendarID, eventID: result.receipt.eventID, sourceKind: account.sourceKind, operation: request.operation, status: .confirmed)
        try await store.applyMutationResult(result, audit: audit)
        return result
    }
}
