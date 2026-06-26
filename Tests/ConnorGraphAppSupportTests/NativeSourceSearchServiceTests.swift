import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Native Source Search Service Tests")
struct NativeSourceSearchServiceTests {
    @Test func timePresetTodayResolvesUsingProvidedTimezone() {
        let timezone = TimeZone(identifier: "Asia/Shanghai")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-06-21T07:36:00Z")!
        let filter = NativeSearchTimePresetResolver.resolve(.today, now: now, timezone: timezone)

        #expect(formatter.string(from: filter.start!) == "2026-06-20T16:00:00Z")
        #expect(formatter.string(from: filter.end!) == "2026-06-21T16:00:00Z")
        #expect(filter.timezoneIdentifier == "Asia/Shanghai")
    }

    @Test func mailTemporalFilterUsesSentAtAndResultsIncludeTime() async throws {
        let service = NativeSourceSearchService()
        let old = ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
        let recent = ISO8601DateFormatter().date(from: "2026-06-20T00:00:00Z")!
        try await service.upsert([
            NativeSearchDocument(
                id: "mail-old",
                sourceKind: .mail,
                sourceInstanceID: "account-a",
                externalID: "old",
                title: "Contract update",
                summary: "Old contract",
                temporal: NativeSearchTemporalMetadata(primaryTime: old, primaryTimeKind: .sentAt, sentAt: old),
                contentHash: "old"
            ),
            NativeSearchDocument(
                id: "mail-recent",
                sourceKind: .mail,
                sourceInstanceID: "account-a",
                externalID: "recent",
                title: "Contract update",
                summary: "Recent contract",
                temporal: NativeSearchTemporalMetadata(primaryTime: recent, primaryTimeKind: .sentAt, sentAt: recent),
                contentHash: "recent"
            )
        ])

        let filter = NativeSearchTemporalFilter(start: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!, end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!, timeFieldPreference: [.sentAt, .receivedAt])
        let results = try await service.search(NativeSearchQuery(text: "contract", sourceKinds: [.mail], temporalFilter: filter, limit: 10))

        #expect(results.map(\.externalID) == ["recent"])
        #expect(results.first?.temporal.primaryTimeKind == .sentAt)
        #expect(results.first?.resultTimeLabel == "Sent")
        #expect(results.first?.resultTimeISO8601 == "2026-06-20T00:00:00Z")
    }

    @Test func rssTemporalFilterUsesPublishedAtAndCanSortByTime() async throws {
        let service = NativeSourceSearchService()
        let first = ISO8601DateFormatter().date(from: "2026-06-18T00:00:00Z")!
        let second = ISO8601DateFormatter().date(from: "2026-06-20T00:00:00Z")!
        try await service.upsert([
            NativeSearchDocument(id: "rss-1", sourceKind: .rss, sourceInstanceID: "feed", externalID: "1", title: "Agent memory", summary: "RSS", temporal: NativeSearchTemporalMetadata(primaryTime: first, primaryTimeKind: .publishedAt, publishedAt: first), contentHash: "1"),
            NativeSearchDocument(id: "rss-2", sourceKind: .rss, sourceInstanceID: "feed", externalID: "2", title: "Agent memory", summary: "RSS", temporal: NativeSearchTemporalMetadata(primaryTime: second, primaryTimeKind: .publishedAt, publishedAt: second), contentHash: "2")
        ])

        let results = try await service.search(NativeSearchQuery(text: "agent", sourceKinds: [.rss], temporalSort: .timeDescThenRelevance, limit: 10))
        #expect(results.map(\.externalID) == ["2", "1"])
        #expect(results.allSatisfy { $0.temporal.publishedAt != nil })
        #expect(results.first?.resultTimeLabel == "Published")
    }

    @Test func calendarTemporalFilterUsesIntervalOverlapByDefault() async throws {
        let service = NativeSourceSearchService()
        let start = ISO8601DateFormatter().date(from: "2026-06-20T23:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-06-21T02:00:00Z")!
        try await service.upsert([
            NativeSearchDocument(
                id: "cal-1",
                sourceKind: .calendar,
                sourceInstanceID: "calendar-a",
                externalID: "event-1",
                title: "Strategy workshop",
                summary: "Cross-day event",
                temporal: NativeSearchTemporalMetadata(primaryTime: start, primaryTimeKind: .eventStartAt, eventStartAt: start, eventEndAt: end, timezoneIdentifier: "Asia/Shanghai"),
                contentHash: "cal-1"
            )
        ])

        let filter = NativeSearchTemporalFilter(
            start: ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!,
            end: ISO8601DateFormatter().date(from: "2026-06-21T01:00:00Z")!,
            mode: .intervalOverlapsRange,
            timezoneIdentifier: "Asia/Shanghai"
        )
        let results = try await service.search(NativeSearchQuery(text: "strategy", sourceKinds: [.calendar], temporalFilter: filter, limit: 10, rankingProfile: .calendarUpcoming))

        #expect(results.map(\.externalID) == ["event-1"])
        #expect(results.first?.temporal.eventStartAt == start)
        #expect(results.first?.temporal.eventEndAt == end)
        #expect(results.first?.resultTimeLabel == "Event starts")
    }

    @Test func chineseSemanticQueryRanksRealPhraseAboveBoundaryGramNoise() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            NativeSearchDocument(
                id: "movie-real",
                sourceKind: .rss,
                externalID: "movie-real",
                title: "西雅图不相信眼泪影评",
                summary: "关于西雅图、不相信与眼泪这些关键词的完整影评。",
                body: "这是一篇讨论西雅图不相信眼泪的电影评论。",
                temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 2_000), primaryTimeKind: .publishedAt, publishedAt: Date(timeIntervalSince1970: 2_000)),
                contentHash: "movie-real"
            ),
            NativeSearchDocument(
                id: "movie-noise",
                sourceKind: .rss,
                externalID: "movie-noise",
                title: "咖啡地图",
                summary: "雅图 图不 不相 信眼 这些碎片只是噪音。",
                body: "雅图 图不 不相 信眼",
                temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 3_000), primaryTimeKind: .publishedAt, publishedAt: Date(timeIntervalSince1970: 3_000)),
                contentHash: "movie-noise"
            )
        ])

        let results = try await service.search(NativeSearchQuery(text: "西雅图眼泪", sourceKinds: [.rss], limit: 10, includeBodySnippets: true))

        #expect(results.first?.id == "movie-real")
        #expect(results.map(\.id).contains("movie-real"))
    }

    @Test func persistentIndexSurvivesRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeSourceSearchServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = root.appendingPathComponent("index.json")
        let time = ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!
        let writer = NativeSourceSearchService(indexURL: indexURL)
        try await writer.upsert([
            NativeSearchDocument(id: "mail-1", sourceKind: .mail, externalID: "mail-1", title: "Persistent search", summary: "hello", temporal: NativeSearchTemporalMetadata(primaryTime: time, primaryTimeKind: .sentAt, sentAt: time), contentHash: "h")
        ])

        let reader = NativeSourceSearchService(indexURL: indexURL)
        let results = try await reader.search(NativeSearchQuery(text: "persistent", sourceKinds: [.mail], limit: 10))
        #expect(results.map(\.externalID) == ["mail-1"])
        #expect(results.first?.resultTimeISO8601 == "2026-06-21T00:00:00Z")
    }
}
