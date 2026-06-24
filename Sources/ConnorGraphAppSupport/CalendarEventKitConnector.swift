import Foundation
import ConnorGraphCore

public struct CalendarEventKitConnector: CalendarSourceConnector {
    public var kind: CalendarSourceKind { .macOSEventKit }

    private let fetchSnapshot: @Sendable () async throws -> CalendarEventKitSnapshot

    public init(fetchSnapshot: @escaping @Sendable () async throws -> CalendarEventKitSnapshot = {
        try await CalendarEventKitAdapter.fetchSystemSnapshot()
    }) {
        self.fetchSnapshot = fetchSnapshot
    }

    public func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult {
        CalendarSourceValidationResult(
            sourceKind: .macOSEventKit,
            status: .ready,
            summary: "macOS Calendar / EventKit 使用系统授权，不需要 Connor 保存额外凭据。"
        )
    }

    public func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection] {
        let snapshot = try await fetchSnapshot()
        return snapshot.collections.map {
            DiscoveredCalendarCollection(id: $0.id, displayName: $0.displayName, colorHex: $0.colorHex, isReadOnly: $0.isReadOnly)
        }
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        let snapshot = try await fetchSnapshot()
        return CalendarSourceSyncResult(
            accountID: request.account.id,
            sourceKind: .macOSEventKit,
            insertedEvents: snapshot.events.count,
            updatedCollections: snapshot.collections.count
        )
    }
}
