import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Memory OS Background Tool Executor Tests")
struct MemoryOSBackgroundToolExecutorTests {
    @Test func rejectsToolsOutsideBackgroundMemoryWhitelist() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))

        #expect(throws: MemoryOSBackgroundToolExecutionError.self) {
            try executor.execute(
                MemoryOSBackgroundToolCall(id: "call-1", name: "shell", argumentsJSON: "{}"),
                context: MemoryOSBackgroundToolExecutionContext(runID: "run-1", iteration: 1)
            )
        }
    }

    @Test func readsProvenanceThroughReadonlyBackgroundTool() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 1_000)
        try store.upsert(provenance: MemoryOSProvenanceObject(
            id: "prov-1",
            sourceType: .chatMessage,
            sourceID: "message-1",
            title: "Evidence",
            content: "Connor Memory OS uses stateless batch prompts.",
            contentHash: "hash-1",
            occurredAt: now,
            ingestedAt: now
        ))
        try store.upsert(span: MemoryOSProvenanceSpan(
            id: "span-1",
            provenanceObjectID: "prov-1",
            startOffset: 0,
            endOffset: 18,
            text: "stateless batch"
        ))
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))

        let result = try executor.execute(
            MemoryOSBackgroundToolCall(
                id: "call-1",
                name: "memory_os_read_provenance",
                argumentsJSON: #"{"provenanceObjectID":"prov-1","spanID":"span-1"}"#
            ),
            context: MemoryOSBackgroundToolExecutionContext(runID: "run-1", iteration: 1)
        )

        #expect(result.name == "memory_os_read_provenance")
        #expect(result.contentText.contains("prov-1"))
        #expect(result.contentJSON.contains("stateless batch"))
        #expect(result.citations == ["prov-1", "span-1"])
    }
}

private func temporaryBackgroundToolDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}
