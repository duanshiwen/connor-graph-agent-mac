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

    @Test func l2UpdateToolAcceptsStatementStringShorthandInBackgroundExecutor() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))

        let result = try executor.execute(
            MemoryOSBackgroundToolCall(
                id: "call-l2-1",
                name: "memory_os_l2_update_entities",
                argumentsJSON: #"{"entities":[{"name":"段福强","type":"person_object","statements":["段福强的英文名是 Oisin。","段福强是段诗闻的弟弟。"]}]}"#
            ),
            context: MemoryOSBackgroundToolExecutionContext(runID: "run-l2-1", iteration: 1)
        )

        #expect(result.name == "memory_os_l2_update_entities")
        #expect(result.contentText.contains("Updated 1 L2 entit(ies)."))
        #expect(result.contentJSON.contains("\"accepted\":true"))
    }

    @Test func l4UpdateToolAcceptsFamilyPredicateAliasInBackgroundExecutor() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))

        let result = try executor.execute(
            MemoryOSBackgroundToolCall(
                id: "call-l4-1",
                name: "memory_os_l4_update_entities",
                argumentsJSON: #"{"entities":[{"name":"段福强","type":"person","summary":"段诗闻的弟弟"},{"name":"段诗闻","type":"person","summary":"当前用户"}],"relations":[{"subjectName":"段福强","predicate":"FAMILY_OF","objectName":"段诗闻","text":"段福强是段诗闻的弟弟"}]}"#
            ),
            context: MemoryOSBackgroundToolExecutionContext(runID: "run-l4-1", iteration: 1)
        )

        #expect(result.name == "memory_os_l4_update_entities")
        #expect(result.contentText.contains("relation"))
        #expect(result.contentJSON.contains("createdRelationCount"))
    }
}

private func temporaryBackgroundToolDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}
