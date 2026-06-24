import Foundation
import ConnorGraphCore

public enum CalendarICSSubscriptionConnectorError: Error, Sendable, Equatable {
    case missingSubscriptionURL
    case invalidResponse
}

public struct CalendarICSSubscriptionConnector: CalendarSourceConnector {
    public var kind: CalendarSourceKind { .icsSubscription }

    private let fetchICS: @Sendable (URL) async throws -> String
    private let parser: ICalendarParser

    public init(
        parser: ICalendarParser = ICalendarParser(),
        fetchICS: @escaping @Sendable (URL) async throws -> String = { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let text = String(data: data, encoding: .utf8) else {
                throw CalendarICSSubscriptionConnectorError.invalidResponse
            }
            return text
        }
    ) {
        self.parser = parser
        self.fetchICS = fetchICS
    }

    public func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult {
        guard configuration.subscriptionURL != nil else {
            return CalendarSourceValidationResult(sourceKind: .icsSubscription, status: .needsConfiguration, summary: "缺少 ICS/Webcal 订阅 URL", blockingReasons: ["missingSubscriptionURL"])
        }
        return CalendarSourceValidationResult(sourceKind: .icsSubscription, status: .ready, summary: "ICS/Webcal 订阅已配置为只读来源")
    }

    public func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection] {
        guard let rawURL = configuration.subscriptionURL else { throw CalendarICSSubscriptionConnectorError.missingSubscriptionURL }
        let url = normalizedSubscriptionURL(rawURL)
        return [DiscoveredCalendarCollection(id: calendarID(for: url), displayName: url.host ?? "ICS 订阅", isReadOnly: true)]
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        guard let rawURL = request.account.configuration.subscriptionURL else { throw CalendarICSSubscriptionConnectorError.missingSubscriptionURL }
        let url = normalizedSubscriptionURL(rawURL)
        let calendarID = calendarID(for: url)
        let ics = try await fetchICS(url)
        let parsedEvents = try parser.events(from: ics)
        let collection = CalendarCollection(
            id: calendarID,
            accountID: request.account.id,
            displayName: request.account.displayName,
            colorHex: "#F97316",
            isReadOnly: true,
            source: "ics-subscription"
        )
        let events = parsedEvents.map { event in
            CalendarEvent(
                id: CalendarEventID(rawValue: "ics-\(request.account.id.rawValue)-\(event.uid)"),
                calendarID: calendarID,
                title: event.summary,
                start: CalendarEventDateTime(date: event.start.date, timeZoneIdentifier: event.start.timeZoneIdentifier),
                end: CalendarEventDateTime(date: event.end?.date ?? event.start.date, timeZoneIdentifier: event.end?.timeZoneIdentifier ?? event.start.timeZoneIdentifier),
                isAllDay: event.isAllDay,
                location: event.location,
                url: event.url,
                notes: event.description,
                recurrenceSummary: event.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)),
                updatedAt: event.lastModified ?? Date()
            )
        }
        return CalendarSourceSyncResult(
            accountID: request.account.id,
            sourceKind: .icsSubscription,
            insertedEvents: events.count,
            updatedCollections: 1,
            collections: [collection],
            events: events
        )
    }

    private func normalizedSubscriptionURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "webcal" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }

    private func calendarID(for url: URL) -> CalendarID {
        let raw = "ics-\(url.absoluteString)"
        let sanitized = raw.lowercased().map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == ".") { return character }
            return "-"
        }
        return CalendarID(rawValue: String(sanitized).replacingOccurrences(of: #"[-.]{2,}"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-.")))
    }
}
