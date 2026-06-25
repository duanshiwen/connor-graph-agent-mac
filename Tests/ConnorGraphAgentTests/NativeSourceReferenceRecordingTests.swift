import Foundation
import Testing
import ConnorGraphAgent

@Suite("Native Source Reference Recording Contract Tests")
struct NativeSourceReferenceRecordingTests {
    @Test func nativeSourceReferenceCarriesSourceStrengthAndToolContext() throws {
        let reference = NativeSourceReference(
            sourceKind: .browserHistory,
            sourceRecordID: "record-1",
            title: "Saved Page",
            content: "# Saved Page\n\nBody markdown",
            occurredAt: Date(timeIntervalSince1970: 2_026),
            accountID: nil,
            sessionID: "session-1",
            url: "https://example.com/page",
            referenceStrength: .detailRead,
            toolName: "browser_history_get",
            toolCallID: "call-1",
            runID: "run-1",
            query: "Saved Page",
            metadata: ["content_status": "fetched"]
        )

        #expect(reference.sourceKind.rawValue == "browser_history")
        #expect(reference.referenceStrength.rawValue == "detail_read")
        #expect(reference.metadata["content_status"] == "fetched")
        #expect(reference.deduplicationKey.contains("browser_history"))
        #expect(reference.deduplicationKey.contains("record-1"))
        #expect(reference.deduplicationKey.contains("detail_read"))
    }

    @Test func nativeSourceReferenceIsCodableForAuditAndTesting() throws {
        let reference = NativeSourceReference(
            sourceKind: .mail,
            sourceRecordID: "message-1",
            title: "Hello",
            content: "Mail body preview",
            occurredAt: Date(timeIntervalSince1970: 1_000),
            accountID: "account-1",
            sessionID: "session-1",
            url: nil,
            referenceStrength: .summaryCandidate,
            toolName: "mail_search_messages",
            toolCallID: "call-1",
            runID: "run-1",
            query: "hello",
            metadata: [:]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(reference)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NativeSourceReference.self, from: data)

        #expect(decoded == reference)
        #expect(decoded.deduplicationKey == reference.deduplicationKey)
    }
}
