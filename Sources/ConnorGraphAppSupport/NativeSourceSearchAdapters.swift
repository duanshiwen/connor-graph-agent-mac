import Foundation
import ConnorGraphCore


public protocol TimeAwareRSSSourceCache: RSSSourceCache {
    func searchItems(query: String, sourceID: RSSSourceID?, includeHidden: Bool, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [RSSItemSummary]
}

public enum NativeSourceSearchAdapters {

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

    public static func browserHistoryDocument(from record: BrowserHistoryRecord, indexedAt: Date = Date()) -> NativeSearchDocument {
        let url = URL(string: record.url)
        let host = url?.host ?? ""
        let path = url?.path ?? ""
        let summary = [host, path].filter { !$0.isEmpty }.joined(separator: " ").isEmpty ? record.url : [host, path].filter { !$0.isEmpty }.joined(separator: " ")
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.url : record.title
        let hash = [
            record.url,
            title,
            record.sessionID,
            record.sessionTitle,
            record.visitedAt.timeIntervalSince1970.description,
            record.contentMarkdown ?? "",
            record.contentFetchStatus?.rawValue ?? ""
        ].joined(separator: "|")
        return NativeSearchDocument(
            id: "browser-history:\(record.id.uuidString)",
            sourceKind: .browserHistory,
            sourceInstanceID: record.sessionID,
            externalID: record.id.uuidString,
            title: title,
            summary: summary,
            body: record.contentMarkdown,
            participants: [record.sessionTitle].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            url: url,
            temporal: NativeSearchTemporalMetadata(primaryTime: record.visitedAt, primaryTimeKind: .updatedAt, updatedAt: record.visitedAt, indexedAt: indexedAt),
            visibility: "visible",
            state: ["contentFetchStatus": record.contentFetchStatus?.rawValue ?? ""],
            metadata: [
                "sessionID": record.sessionID,
                "sessionTitle": record.sessionTitle,
                "url": record.url,
                "host": host,
                "path": path,
                "contentFetchedAt": record.contentFetchedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "contentFetchError": record.contentFetchError ?? ""
            ],
            contentHash: stableHash(hash)
        )
    }

    public static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public extension NativeSearchTemporalFilter {
    static func sourceDefault(start: Date?, end: Date?, sourceKind: NativeSearchSourceKind, timezoneIdentifier: String = TimeZone.current.identifier) -> NativeSearchTemporalFilter? {
        guard start != nil || end != nil else { return nil }
        switch sourceKind {
        case .rss:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .pointWithinRange, timeFieldPreference: [.publishedAt, .fetchedAt], timezoneIdentifier: timezoneIdentifier)
        case .calendar:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .intervalOverlapsRange, timeFieldPreference: [.eventStartAt], timezoneIdentifier: timezoneIdentifier)
        case .browserHistory:
            return NativeSearchTemporalFilter(start: start, end: end, mode: .pointWithinRange, timeFieldPreference: [.updatedAt, .createdAt], timezoneIdentifier: timezoneIdentifier)
        }
    }
}
