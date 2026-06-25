import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("App Memory OS Native Source Reference Recorder Tests")
struct AppMemoryOSNativeSourceReferenceRecorderTests {
    @Test func recorderPersistsReferencesIntoL0AndL1WithMetadata() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryNativeSourceReferenceRecorderDatabaseURL().path)
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        let recorder = AppMemoryOSNativeSourceReferenceRecorder(facade: facade)
        let reference = NativeSourceReference(
            sourceKind: .browserHistory,
            sourceRecordID: "browser-1",
            title: "Saved Browser Page",
            content: "# Saved Browser Page\n\nMarkdown body used by the LLM.",
            occurredAt: Date(timeIntervalSince1970: 12_000),
            sessionID: "session-1",
            url: "https://example.com/saved",
            referenceStrength: .detailRead,
            toolName: "browser_history_get",
            toolCallID: "call-browser-get",
            runID: "run-1",
            query: nil,
            metadata: ["content_fetch_status": "fetched"]
        )

        await recorder.record([reference])

        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "1")
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
        let l0 = try #require(try store.query(sql: "SELECT source_id, source_type, title, content, metadata_json FROM memory_l0_provenance_objects;").first)
        #expect(l0[0].contains("native-ref:browser_history:browser-1:detail_read"))
        #expect(l0[1] == "source_event")
        #expect(l0[2] == "Saved Browser Page")
        #expect(l0[3].contains("Markdown body used by the LLM"))
        #expect(l0[4].contains("browser_history"))
        #expect(l0[4].contains("browser_history_get"))
        #expect(l0[4].contains("call-browser-get"))
        #expect(l0[4].contains("detail_read"))
    }
}

private func temporaryNativeSourceReferenceRecorderDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("native-source-reference-recorder-\(UUID().uuidString).sqlite")
}
