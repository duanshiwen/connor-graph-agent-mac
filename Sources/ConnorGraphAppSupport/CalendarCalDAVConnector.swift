import Foundation
import ConnorGraphCore

public enum CalendarCalDAVConnectorError: Error, Sendable, Equatable {
    case missingServerURL
    case missingCredential
    case unsupportedSourceKind(CalendarSourceKind)
}

public struct CalendarCalDAVConnector: CalendarSourceConnector {
    public let kind: CalendarSourceKind

    private let discoveryService: CalendarCalDAVDiscoveryService
    private let eventFetcher: CalendarCalDAVEventFetcher
    private let now: @Sendable () -> Date

    public init(
        kind: CalendarSourceKind = .genericCalDAV,
        discoveryService: CalendarCalDAVDiscoveryService = CalendarCalDAVDiscoveryService(),
        eventFetcher: CalendarCalDAVEventFetcher = CalendarCalDAVEventFetcher(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.kind = kind
        self.discoveryService = discoveryService
        self.eventFetcher = eventFetcher
        self.now = now
    }

    public func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult {
        guard configuration.serverURL != nil else {
            return CalendarSourceValidationResult(sourceKind: kind, status: .needsConfiguration, summary: "缺少 CalDAV 服务器 URL", blockingReasons: ["missingServerURL"])
        }
        guard credential?.isEmpty == false else {
            return CalendarSourceValidationResult(sourceKind: kind, status: .unauthenticated, summary: "缺少 CalDAV 凭据", blockingReasons: ["missingCredential"])
        }
        return CalendarSourceValidationResult(sourceKind: kind, status: .ready, summary: "CalDAV 只读来源已配置")
    }

    public func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection] {
        guard let serverURL = configuration.serverURL else { throw CalendarCalDAVConnectorError.missingServerURL }
        guard credential?.isEmpty == false else { throw CalendarCalDAVConnectorError.missingCredential }
        return try await discoveryService.discover(baseURL: serverURL, credential: credential).collections
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        guard request.account.sourceKind == .genericCalDAV || request.account.sourceKind == .appleICloudCalDAV || request.account.sourceKind == .fastmailCalDAV || request.account.sourceKind == .nextcloudCalDAV else {
            throw CalendarCalDAVConnectorError.unsupportedSourceKind(request.account.sourceKind)
        }
        guard let serverURL = request.account.configuration.serverURL else { throw CalendarCalDAVConnectorError.missingServerURL }
        guard request.credential?.isEmpty == false else { throw CalendarCalDAVConnectorError.missingCredential }
        let discovery = try await discoveryService.discover(baseURL: serverURL, credential: request.credential)
        let collections = discovery.collections.map { discovered in
            CalendarCollection(
                id: discovered.id,
                accountID: request.account.id,
                displayName: discovered.displayName,
                colorHex: discovered.colorHex,
                isReadOnly: true,
                source: "caldav"
            )
        }
        let enabledIDs = Set(request.account.configuration.enabledCollectionIDs)
        let selectedCollections = enabledIDs.isEmpty ? collections : collections.filter { enabledIDs.contains($0.id) }
        let window = syncWindow(configuration: request.account.configuration)
        var events: [CalendarEvent] = []
        for collection in selectedCollections {
            guard let url = discovery.collectionURLs[collection.id] else { continue }
            let fetched = try await eventFetcher.fetchEvents(collection: collection, collectionURL: url, credential: request.credential, windowStart: window.start, windowEnd: window.end)
            events.append(contentsOf: fetched)
        }
        return CalendarSourceSyncResult(
            accountID: request.account.id,
            sourceKind: request.account.sourceKind,
            insertedEvents: events.count,
            updatedCollections: collections.count,
            diagnostics: selectedCollections.count < collections.count ? [CalendarSourceSyncDiagnostic(code: "collectionsFiltered", summary: "Filtered \(collections.count - selectedCollections.count) disabled CalDAV collections")] : [],
            collections: selectedCollections,
            events: events.sorted { $0.start.date < $1.start.date }
        )
    }

    private func syncWindow(configuration: CalendarSourceConfiguration) -> (start: Date, end: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let current = now()
        let start = calendar.date(byAdding: .day, value: -configuration.syncWindowPastDays, to: current) ?? current
        let end = calendar.date(byAdding: .day, value: configuration.syncWindowFutureDays, to: current) ?? current
        return (start, end)
    }
}
