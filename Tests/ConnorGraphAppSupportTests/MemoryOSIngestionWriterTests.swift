import Foundation
import Testing
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("MemoryOS Ingestion Writer Tests")
struct MemoryOSIngestionWriterTests {
    @Test func flushPersistsQueuedChatMessagesThroughFacade() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        let writer = MemoryOSIngestionWriter(facade: facade)
        let now = Date(timeIntervalSince1970: 1_000)

        await writer.enqueueChatMessage(messageID: "msg-1", sessionID: "session", role: "user", content: "Hello", occurredAt: now)
        try await writer.flush()

        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
    }
}
