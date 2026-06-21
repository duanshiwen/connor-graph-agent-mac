import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Native Source Search Mail/RSS Integration Tests")
struct NativeSourceSearchMailRSSTests {
    @Test func fileBackedMailSearchFiltersBySentDateAndIndexesBody() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MailIndexedSearch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("mail-store.json")
        let search = NativeSourceSearchService(indexURL: root.appendingPathComponent("index.json"))
        let store = FileBackedMailSourceStore(storeURL: storeURL, searchService: search)
        let accountID = MailAccountID(rawValue: "account")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let oldDate = ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
        let recentDate = ISO8601DateFormatter().date(from: "2026-06-20T00:00:00Z")!

        let old = MailMessageDetail(summary: MailMessageSummary(id: MailMessageID(rawValue: "old"), accountID: accountID, mailboxID: mailboxID, subject: "Contract", from: MailAddress(email: "old@example.com"), to: [], date: oldDate, snippet: "old"), body: MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "needle legacy body", byteCount: 18), redactedPreview: "needle legacy body"))
        let recent = MailMessageDetail(summary: MailMessageSummary(id: MailMessageID(rawValue: "recent"), accountID: accountID, mailboxID: mailboxID, subject: "Contract", from: MailAddress(email: "new@example.com"), to: [], date: recentDate, snippet: "recent"), body: MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "needle current body", byteCount: 18), redactedPreview: "needle current body"))
        try await store.saveMessage(old)
        try await store.saveMessage(recent)

        let filter = NativeSearchTemporalFilter(start: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!, end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!, timeFieldPreference: [.sentAt])
        let results = try await store.searchMessages(query: "needle", accountID: accountID, temporalFilter: filter, temporalSort: .timeDescThenRelevance, limit: 10)

        #expect(results.map(\.id) == [MailMessageID(rawValue: "recent")])
        #expect(results.first?.date == recentDate)
    }

    @Test func fileBackedRSSSearchFiltersByPublishedDateAndIndexesContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RSSIndexedSearch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let search = NativeSourceSearchService(indexURL: root.appendingPathComponent("index.json"))
        let cache = FileBackedRSSSourceCache(storageDirectory: root, searchService: search)
        let sourceID = RSSSourceID(rawValue: "feed")
        let oldDate = ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
        let recentDate = ISO8601DateFormatter().date(from: "2026-06-20T00:00:00Z")!

        let old = RSSItemDetail(summary: RSSItemSummary(id: RSSItemID(rawValue: "old"), sourceID: sourceID, title: "Agent", publishedAt: oldDate, snippet: "old", contentHash: "old"), content: RSSItemContent(safeMarkdown: "vector memory", plainText: "vector memory"))
        let recent = RSSItemDetail(summary: RSSItemSummary(id: RSSItemID(rawValue: "recent"), sourceID: sourceID, title: "Agent", publishedAt: recentDate, snippet: "recent", contentHash: "recent"), content: RSSItemContent(safeMarkdown: "vector memory", plainText: "vector memory"))
        _ = try await cache.upsertItems([old, recent])

        let filter = NativeSearchTemporalFilter(start: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!, end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!, timeFieldPreference: [.publishedAt, .fetchedAt])
        let results = try await cache.searchItems(query: "vector", sourceID: sourceID, includeHidden: false, temporalFilter: filter, temporalSort: .timeDescThenRelevance, limit: 10)

        #expect(results.map(\.id) == [RSSItemID(rawValue: "recent")])
        #expect(results.first?.publishedAt == recentDate)
    }
}
