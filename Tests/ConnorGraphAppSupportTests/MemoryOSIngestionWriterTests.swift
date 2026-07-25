import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("MemoryOS Ingestion Writer Tests")
struct MemoryOSIngestionWriterTests {
    @Test func normalizationPolicyExemptsOnlyFirstUserMessageInNoteSession() {
        let policy = MemoryOSUserIntentNormalizationPolicy()

        #expect(!policy.shouldNormalize(role: "user", sessionKind: .note, isFirstUserMessage: true))
        #expect(policy.shouldNormalize(role: "user", sessionKind: .note, isFirstUserMessage: false))
        #expect(policy.shouldNormalize(role: "user", sessionKind: .chat, isFirstUserMessage: true))
        #expect(!policy.shouldNormalize(role: "assistant", sessionKind: .note, isFirstUserMessage: false))
    }

    @Test func firstNoteMessageBypassesNormalizerAndUsesOriginalRetrievalText() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        let normalizer = AnyMemoryOSUserIntentNormalizer { _ in
            Issue.record("The first note message must not invoke user-intent normalization")
            throw MemoryOSUserIntentNormalizerError.missingStructuredOutput
        }
        let writer = MemoryOSIngestionWriter(facade: facade, intentNormalizer: normalizer)

        await writer.enqueueChatMessage(
            messageID: "note-first",
            sessionID: "note-session",
            role: "user",
            content: "保留这段笔记原文",
            occurredAt: Date(timeIntervalSince1970: 1_000),
            sessionKind: .note,
            isFirstUserMessage: true
        )
        try await writer.flush()

        let row = try #require(try store.query(sql: """
        SELECT c.retrieval_text, c.normalization_status, c.metadata_json
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE o.source_id = 'note-first'
        """).first)
        #expect(row[0] == "保留这段笔记原文")
        #expect(row[1] == MemoryOSIntentNormalizationStatus.notRequired.rawValue)
        #expect(row[2].contains("initial_note_message"))
    }

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
