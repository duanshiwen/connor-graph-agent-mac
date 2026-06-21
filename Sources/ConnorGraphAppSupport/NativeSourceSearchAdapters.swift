import Foundation
import ConnorGraphCore

public protocol TimeAwareMailSourceCache: MailSourceCache {
    func searchMessages(query: String, accountID: MailAccountID?, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [MailMessageSummary]
}

public protocol TimeAwareRSSSourceCache: RSSSourceCache {
    func searchItems(query: String, sourceID: RSSSourceID?, includeHidden: Bool, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [RSSItemSummary]
}

public enum NativeSourceSearchAdapters {
    public static func mailDocument(from detail: MailMessageDetail) -> NativeSearchDocument {
        let summary = detail.summary
        let bodyText = detail.body?.plainText?.text ?? detail.body?.redactedPreview
        let participants = ([summary.from.email] + summary.to.map(\.email) + summary.cc.map(\.email))
        let hash = [summary.subject, summary.snippet, bodyText ?? "", summary.date.timeIntervalSince1970.description, summary.flags.isRead.description].joined(separator: "|")
        return NativeSearchDocument(
            id: "mail:\(summary.id.rawValue)",
            sourceKind: .mail,
            sourceInstanceID: summary.accountID.rawValue,
            externalID: summary.id.rawValue,
            title: summary.subject,
            summary: summary.snippet,
            body: bodyText,
            participants: participants,
            temporal: NativeSearchTemporalMetadata(primaryTime: summary.date, primaryTimeKind: .sentAt, sentAt: summary.date, indexedAt: Date()),
            visibility: "visible",
            state: ["isRead": summary.flags.isRead ? "true" : "false"],
            metadata: ["mailboxID": summary.mailboxID.rawValue, "from": summary.from.email],
            contentHash: stableHash(hash)
        )
    }

    public static func rssDocument(from detail: RSSItemDetail) -> NativeSearchDocument {
        let summary = detail.summary
        let bodyText = detail.content?.plainText ?? detail.content?.safeMarkdown
        let hash = [summary.title, summary.snippet, bodyText ?? "", summary.publishedAt.timeIntervalSince1970.description, summary.state.isHidden.description, summary.state.isRead.description, summary.state.isStarred.description].joined(separator: "|")
        return NativeSearchDocument(
            id: "rss:\(summary.id.rawValue)",
            sourceKind: .rss,
            sourceInstanceID: summary.sourceID.rawValue,
            externalID: summary.id.rawValue,
            title: summary.title,
            summary: summary.snippet,
            body: bodyText,
            participants: [summary.author].compactMap { $0 },
            url: summary.link,
            temporal: NativeSearchTemporalMetadata(primaryTime: summary.publishedAt, primaryTimeKind: .publishedAt, publishedAt: summary.publishedAt, fetchedAt: summary.fetchedAt, indexedAt: Date()),
            visibility: summary.state.isHidden ? "hidden" : "visible",
            state: ["isRead": summary.state.isRead ? "true" : "false", "isStarred": summary.state.isStarred ? "true" : "false", "isHidden": summary.state.isHidden ? "true" : "false"],
            metadata: ["sourceID": summary.sourceID.rawValue, "author": summary.author ?? ""],
            contentHash: summary.contentHash.isEmpty ? stableHash(hash) : summary.contentHash
        )
    }

    public static func calendarDocument(from event: CalendarEvent) -> NativeSearchDocument {
        let attendees = event.attendees.map { [$0.name, $0.email].compactMap { $0 }.joined(separator: " ") }
        let body = [event.notes, event.location, event.recurrenceSummary?.ruleDescription].compactMap { $0 }.joined(separator: "\n")
        let hash = [event.title, body, event.start.date.timeIntervalSince1970.description, event.end.date.timeIntervalSince1970.description, event.updatedAt.timeIntervalSince1970.description].joined(separator: "|")
        return NativeSearchDocument(
            id: "calendar:\(event.id.rawValue)",
            sourceKind: .calendar,
            sourceInstanceID: event.calendarID.rawValue,
            externalID: event.id.rawValue,
            title: event.title,
            summary: event.notes ?? event.location ?? "",
            body: body,
            participants: attendees,
            location: event.location,
            url: event.url,
            temporal: NativeSearchTemporalMetadata(primaryTime: event.start.date, primaryTimeKind: .eventStartAt, updatedAt: event.updatedAt, eventStartAt: event.start.date, eventEndAt: event.end.date, indexedAt: Date(), timezoneIdentifier: event.start.timeZoneIdentifier, isAllDay: event.isAllDay),
            visibility: "visible",
            metadata: ["calendarID": event.calendarID.rawValue],
            contentHash: stableHash(hash)
        )
    }

    public static func stableHash(_ value: String) -> String {
        String(value.hashValue)
    }
}

public extension NativeSearchTemporalFilter {
    static func sourceDefault(start: Date?, end: Date?, sourceKind: NativeSearchSourceKind, timezoneIdentifier: String = TimeZone.current.identifier) -> NativeSearchTemporalFilter? {
        guard start != nil || end != nil else { return nil }
        switch sourceKind {
        case .mail:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .pointWithinRange, timeFieldPreference: [.sentAt, .receivedAt], timezoneIdentifier: timezoneIdentifier)
        case .rss:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .pointWithinRange, timeFieldPreference: [.publishedAt, .fetchedAt], timezoneIdentifier: timezoneIdentifier)
        case .calendar:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .intervalOverlapsRange, timeFieldPreference: [.eventStartAt], timezoneIdentifier: timezoneIdentifier)
        }
    }
}
