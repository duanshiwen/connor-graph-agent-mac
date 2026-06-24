import Foundation
import ConnorGraphCore

public struct CalendarSourceDiagnosticsPresentation: Sendable, Equatable {
    public var cards: [CalendarSourceDiagnosticsCard]

    public init(cards: [CalendarSourceDiagnosticsCard] = []) {
        self.cards = cards
    }
}

public struct CalendarSourceDiagnosticsCard: Sendable, Equatable, Identifiable {
    public var id: CalendarAccountID
    public var displayName: String
    public var sourceKind: CalendarSourceKind
    public var status: CalendarAccountHealthStatus
    public var collectionCount: Int
    public var eventCount: Int
    public var lastSuccessfulSyncAt: Date?
    public var nextRetryAt: Date?
    public var failureCount: Int
    public var lastDiagnosticMessage: String?

    public init(id: CalendarAccountID, displayName: String, sourceKind: CalendarSourceKind, status: CalendarAccountHealthStatus, collectionCount: Int, eventCount: Int, lastSuccessfulSyncAt: Date? = nil, nextRetryAt: Date? = nil, failureCount: Int = 0, lastDiagnosticMessage: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.sourceKind = sourceKind
        self.status = status
        self.collectionCount = collectionCount
        self.eventCount = eventCount
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.nextRetryAt = nextRetryAt
        self.failureCount = failureCount
        self.lastDiagnosticMessage = lastDiagnosticMessage
    }
}

public struct CalendarSourceDiagnosticsPresentationBuilder: Sendable {
    public init() {}

    public func build(snapshot: CalendarSourceRuntimeSnapshot) -> CalendarSourceDiagnosticsPresentation {
        let cards = snapshot.accounts.map { account in
            let collections = snapshot.collections.filter { $0.accountID == account.id }
            let collectionIDs = Set(collections.map(\.id))
            let events = snapshot.events.filter { collectionIDs.contains($0.calendarID) }
            let syncState = snapshot.syncStates.first { $0.accountID == account.id }
            let diagnostics = snapshot.diagnostics.filter { $0.accountID == account.id }
            let lastDiagnostic = diagnostics.sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }.first
            return CalendarSourceDiagnosticsCard(
                id: account.id,
                displayName: account.displayName,
                sourceKind: account.sourceKind,
                status: resolvedStatus(account: account, syncState: syncState, diagnostics: diagnostics),
                collectionCount: collections.count,
                eventCount: events.count,
                lastSuccessfulSyncAt: syncState?.lastSuccessfulSyncAt,
                nextRetryAt: syncState?.nextRetryAt,
                failureCount: syncState?.failureCount ?? 0,
                lastDiagnosticMessage: lastDiagnostic?.message
            )
        }
        return CalendarSourceDiagnosticsPresentation(cards: cards.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
    }

    private func resolvedStatus(account: CalendarAccount, syncState: CalendarAccountSyncState?, diagnostics: [CalendarSourceSyncDiagnostic]) -> CalendarAccountHealthStatus {
        if diagnostics.contains(where: { $0.severity == .error }) { return .degraded }
        if syncState?.lastSuccessfulSyncAt != nil { return .ready }
        return account.health.status
    }
}
