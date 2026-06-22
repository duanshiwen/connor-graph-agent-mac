import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func memoryOSSearchToolReturnsLayerAwareHits() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    _ = try facade.ingestChatMessage(messageID: "message-1", sessionID: "session", role: "user", content: "Connor Memory OS needs unified retrieval.", occurredAt: now)
    let node = MemoryOSNode(id: "node-1", stableKey: "node-1", nodeType: "project", name: "Connor Memory OS")
    try store.upsert(node: node)
    try store.upsert(statement: MemoryOSStatement(id: "stmt-1", subjectID: node.id, predicate: "needs", text: "Connor Memory OS needs unified retrieval.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"]))

    let tool = MemoryOSSearchTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Connor Memory OS retrieval","layers":["L1","L2"],"limit":5}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_search")
    #expect(result.contentText.contains("Memory OS search returned"))
    #expect(json.contains("\"layer\":\"L1\"") || json.contains("\"layer\":\"L2\""))
    #expect(json.contains("Connor Memory OS"))
}

@Test func memoryOSExpandL4ToolReturnsDepthExpansion() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    let entityA = MemoryOSEntity(id: "entity-a", stableKey: "entity-a", entityType: "concept", name: "供需弹性", createdAt: now, updatedAt: now)
    let entityB = MemoryOSEntity(id: "entity-b", stableKey: "entity-b", entityType: "concept", name: "价格变化", createdAt: now, updatedAt: now)
    try store.upsert(entity: entityA)
    try store.upsert(entity: entityB)
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "l4-stmt-1", entityID: entityA.id, predicate: "relates_to", objectEntityID: entityB.id, text: "供需弹性关联价格变化。", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"]))

    let tool = MemoryOSExpandL4Tool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"entityID":"entity-a","depth":1,"limit":10}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_expand_l4")
    #expect(result.contentText.contains("L4 expansion returned"))
    #expect(json.contains("l4-stmt-1"))
    #expect(json.contains("entity-b"))
}

private func memoryOSToolContext() -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run-memory-os-retrieval", sessionID: "session", groupID: "group", userPrompt: "search memory", toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
}

private func temporaryAppMemoryOSRetrievalToolDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-retrieval-tool-\(UUID().uuidString).sqlite")
}
