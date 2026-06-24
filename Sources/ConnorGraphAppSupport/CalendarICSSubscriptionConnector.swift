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
    private let now: @Sendable () -> Date

    public init(
        parser: ICalendarParser = ICalendarParser(),
        now: @escaping @Sendable () -> Date = Date.init,
        fetchICS: @escaping @Sendable (URL) async throws -> String = { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CalendarICSSubscriptionConnectorError.invalidResponse
            }
            return text
        }
    ) {
        self.parser = parser
        self.now = now
        self.fetchICS = fetchICS
    }

    public func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult {
        guard let url = configuration.subscriptionURL else {
            return CalendarSourceValidationResult(sourceKind: .icsSubscription, status: .needsConfiguration, summary: "缺少 ICS/Webcal 订阅 URL", blockingReasons: ["missingSubscriptionURL"])
        }
        guard isSupportedSubscriptionURL(url) else {
            return CalendarSourceValidationResult(sourceKind: .icsSubscription, status: .blocked, summary: "ICS/Webcal 订阅 URL 只支持 http、https 或 webcal", blockingReasons: ["unsupportedURLScheme"])
        }
        return CalendarSourceValidationResult(sourceKind: .icsSubscription, status: .ready, summary: "ICS/Webcal 订阅已配置为只读来源")
    }

    public func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection] {
        guard let rawURL = configuration.subscriptionURL else { throw CalendarICSSubscriptionConnectorError.missingSubscriptionURL }
        guard isSupportedSubscriptionURL(rawURL) else { throw CalendarICSSubscriptionConnectorError.invalidResponse }
        let url = normalizedSubscriptionURL(rawURL)
        return [DiscoveredCalendarCollection(id: calendarID(for: url), displayName: url.host ?? "ICS 订阅", isReadOnly: true)]
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        guard let rawURL = request.account.configuration.subscriptionURL else { throw CalendarICSSubscriptionConnectorError.missingSubscriptionURL }
        guard isSupportedSubscriptionURL(rawURL) else { throw CalendarICSSubscriptionConnectorError.invalidResponse }
        let url = normalizedSubscriptionURL(rawURL)
        let calendarID = calendarID(for: url)
        let ics = try await fetchICS(url)
        let parsedEvents = try parser.events(from: ics)
        let filteredParsedEvents = parsedEvents.filter { event in
            overlapsSyncWindow(start: event.start.date, end: event.end?.date ?? event.start.date, configuration: request.account.configuration)
        }
        let filteredCount = max(0, parsedEvents.count - filteredParsedEvents.count)
        let collection = CalendarCollection(
            id: calendarID,
            accountID: request.account.id,
            displayName: request.account.displayName,
            colorHex: "#F97316",
            isReadOnly: true,
            source: "ics-subscription"
        )
        let events = filteredParsedEvents.map { event in
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
                attendees: event.attendees.enumerated().map { index, attendee in
                    CalendarAttendee(
                        id: CalendarAttendeeID(rawValue: "ics-\(request.account.id.rawValue)-\(event.uid)-attendee-\(index)"),
                        name: attendee.name,
                        email: attendee.email,
                        role: calendarRole(from: attendee.role),
                        responseStatus: calendarResponseStatus(from: attendee.participationStatus)
                    )
                },
                recurrenceSummary: event.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)),
                updatedAt: event.lastModified ?? now()
            )
        }
        return CalendarSourceSyncResult(
            accountID: request.account.id,
            sourceKind: .icsSubscription,
            insertedEvents: events.count,
            updatedCollections: 1,
            diagnostics: filteredCount > 0 ? [CalendarSourceSyncDiagnostic(code: "eventsFilteredBySyncWindow", summary: "Filtered \(filteredCount) events outside the configured sync window")] : [],
            collections: [collection],
            events: events
        )
    }

    private func calendarRole(from role: String?) -> CalendarAttendeeRole {
        switch role?.uppercased() {
        case "REQ-PARTICIPANT": return .required
        case "OPT-PARTICIPANT": return .optional
        case "NON-PARTICIPANT": return .resource
        default: return .unknown
        }
    }

    private func calendarResponseStatus(from status: String?) -> CalendarAttendeeResponseStatus {
        switch status?.uppercased() {
        case "NEEDS-ACTION": return .needsAction
        case "ACCEPTED": return .accepted
        case "DECLINED": return .declined
        case "TENTATIVE": return .tentative
        case "DELEGATED": return .delegated
        default: return .unknown
        }
    }

    private func isSupportedSubscriptionURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "webcal"
    }

    private func overlapsSyncWindow(start: Date, end: Date, configuration: CalendarSourceConfiguration) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let current = now()
        let lower = calendar.date(byAdding: .day, value: -configuration.syncWindowPastDays, to: current) ?? current
        let upper = calendar.date(byAdding: .day, value: configuration.syncWindowFutureDays, to: current) ?? current
        return end >= lower && start <= upper
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
