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

    @Test func exposesSeparatedBackgroundContextToolsAndRejectsLegacyTool() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 2_000)
        try store.upsert(node: MemoryOSNode(id: "project", stableKey: "project:context", nodeType: "project", name: "Context Split"))
        try store.upsert(statement: MemoryOSStatement(id: "status", subjectID: "project", predicate: "status", text: "Context Split is currently active.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: []))
        try store.upsert(belief: MemoryOSBelief(id: "belief", statement: "Context Split separates operational and durable semantics.", domain: "knowledge", relatedObjectNames: "Context Split", createdAt: now, updatedAt: now))
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))
        let context = MemoryOSBackgroundToolExecutionContext(runID: "run", iteration: 1)

        let recent = try executor.execute(MemoryOSBackgroundToolCall(id: "recent", name: "memory_os_recent_context", argumentsJSON: #"{"query":"Context Split"}"#), context: context)
        let knowledge = try executor.execute(MemoryOSBackgroundToolCall(id: "knowledge", name: "memory_os_knowledge_context", argumentsJSON: #"{"query":"Context Split"}"#), context: context)

        #expect(recent.contentText.contains("currently active"))
        #expect(!recent.contentText.contains("durable semantics"))
        #expect(knowledge.contentText.contains("durable semantics"))
        #expect(!knowledge.contentText.contains("currently active"))
        let recentResponse = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(recent.contentJSON.utf8))
        #expect(recentResponse.requestedLimit == 10)
        #expect(recentResponse.records.contains { $0.recordID == "status" && $0.layer == "L2" })
        #expect(recent.citations.contains("status"))
        #expect(recentResponse.hasMore == nil)
        #expect(recentResponse.partial == false)
        #expect(throws: MemoryOSBackgroundToolExecutionError.self) {
            try executor.execute(MemoryOSBackgroundToolCall(id: "legacy", name: "memory_os_context", argumentsJSON: #"{"query":"Context Split"}"#), context: context)
        }
    }

    @Test func contextLimitExpansionReturnsOnlyNewStructuredRecordsWithinRun() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 3_000)
        for index in 0..<6 {
            try store.upsert(belief: MemoryOSBelief(
                id: "belief-\(index)",
                statement: "Incremental protocol evidence \(index)",
                domain: "reliability",
                relatedObjectNames: "Incremental protocol",
                createdAt: now.addingTimeInterval(Double(index)),
                updatedAt: now.addingTimeInterval(Double(index))
            ))
        }
        let executor = MemoryOSBackgroundToolExecutor(
            facade: AppMemoryOSFacade(store: store),
            contextToolConfiguration: .init(minimumResultLimit: 2, defaultResultLimit: 2, maxDepth: 4)
        )
        let context = MemoryOSBackgroundToolExecutionContext(runID: "incremental-run", iteration: 1)

        let first = try executor.execute(
            .init(id: "first", name: "memory_os_knowledge_context", argumentsJSON: #"{"query":"Incremental protocol","limit":2}"#),
            context: context
        )
        let expanded = try executor.execute(
            .init(id: "expanded", name: "memory_os_knowledge_context", argumentsJSON: #"{"query":"Incremental protocol","limit":5}"#),
            context: context
        )
        let firstResponse = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(first.contentJSON.utf8))
        let expandedResponse = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(expanded.contentJSON.utf8))

        #expect(firstResponse.returnedCount == 2)
        #expect(firstResponse.cumulativeReturnedCount == 2)
        #expect(expandedResponse.returnedCount == 3)
        #expect(expandedResponse.cumulativeReturnedCount == 5)
        #expect(Set(firstResponse.records.map(\.recordID)).isDisjoint(with: expandedResponse.records.map(\.recordID)))
        #expect(expandedResponse.records.allSatisfy { $0.depth == 0 && $0.status == "active" })
    }

    @Test func backgroundContextToolSupportsEmptyQueryTimeRange() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryBackgroundToolDatabaseURL().path)
        try store.migrate()
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(1_000)
        try store.upsert(node: MemoryOSNode(id: "range-project", stableKey: "range-project", nodeType: "project", name: "Range Project"))
        let object = MemoryOSProvenanceObject(id: "range-object", sourceType: .chatMessage, title: "Range", content: "Background period record", occurredAt: start.addingTimeInterval(100), ingestedAt: end.addingTimeInterval(100))
        try store.upsert(provenance: object)
        try store.upsert(span: MemoryOSProvenanceSpan(id: "range-span", provenanceObjectID: object.id, text: object.content))
        try store.upsert(statement: MemoryOSStatement(id: "range-inside", subjectID: "range-project", predicate: "status", text: "Background period record", confidence: 0.9, validAt: end.addingTimeInterval(100), committedAt: end.addingTimeInterval(100), evidenceSpanIDs: ["range-span"]))
        let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))

        let result = try executor.execute(
            .init(id: "range", name: "memory_os_recent_context", argumentsJSON: """
            {"query":"","startDate":"\(ISO8601DateFormatter().string(from: start))","endDate":"\(ISO8601DateFormatter().string(from: end))"}
            """),
            context: .init(runID: "range-run", iteration: 1)
        )
        let response = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(result.contentJSON.utf8))
        #expect(response.query.isEmpty)
        #expect(response.records.contains { $0.recordID == "range-inside" && $0.occurredAt == ISO8601DateFormatter().string(from: object.occurredAt) })
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
