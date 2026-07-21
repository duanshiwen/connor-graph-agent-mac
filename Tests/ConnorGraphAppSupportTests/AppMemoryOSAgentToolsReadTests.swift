import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func memoryOSReadRecordToolReadsL2Statement() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSReadToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    try store.upsert(node: MemoryOSNode(id: "node-1", stableKey: "node-1", nodeType: "project", name: "Memory OS"))
    try store.upsert(statement: MemoryOSStatement(id: "stmt-1", subjectID: "node-1", predicate: "requires", text: "L2 facts require evidence refs.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"]))

    let tool = MemoryOSReadRecordTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"layer":"L2","recordID":"stmt-1"}"#), context: memoryOSReadToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_read_record")
    #expect(json.contains("stmt-1"))
    #expect(json.contains("L2 facts require evidence refs"))
    #expect(json.contains("span-1"))
}

@Test func memoryOSReadRecordToolReadsL3KnowledgeRecord() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSReadToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    try store.upsert(belief: MemoryOSBelief(id: "belief-1", statement: "L3 records require reusable cognitive structure.", domain: "knowledge-management", relatedObjectNames: "Prompt governance", createdAt: now, updatedAt: now))

    let tool = MemoryOSReadRecordTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"layer":"L3","recordID":"belief-1"}"#), context: memoryOSReadToolContext())

    let json = try #require(result.contentJSON)
    #expect(json.contains("belief-1"))
    #expect(json.contains("knowledge-management"))
    #expect(json.contains("Prompt governance"))
}

@Test func memoryOSReadProvenanceToolReadsL0ObjectAndSpan() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSReadToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    try store.upsert(provenance: MemoryOSProvenanceObject(id: "prov-1", sourceType: .manual, sourceID: "source-1", title: "Prompt note", content: "Full raw content about structured L1 event packets.", occurredAt: now, metadata: ["kind": "note"]))
    try store.upsert(span: MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: "prov-1", startOffset: 0, endOffset: 17, text: "Full raw content", metadata: ["field": "body"]))

    let tool = MemoryOSReadProvenanceTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"provenanceObjectID":"prov-1","spanID":"span-1"}"#), context: memoryOSReadToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_read_provenance")
    #expect(json.contains("prov-1"))
    #expect(json.contains("span-1"))
    #expect(json.contains("Full raw content"))
    #expect(json.contains("Prompt note"))
}

@Test func toolRegistryRegistersMemoryOSReadTools() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSReadToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    var registry = AgentToolRegistry()

    registry.registerMemoryOSReadTools(facade: facade)

    let recentDefinition = try #require(registry.definition(named: "memory_os_recent_context"))
    let knowledgeDefinition = try #require(registry.definition(named: "memory_os_knowledge_context"))
    let profileDefinition = try #require(registry.definition(named: "memory_os_get_current_user_profile"))
    #expect(recentDefinition.description.contains("L1") && recentDefinition.description.contains("L2"))
    #expect(knowledgeDefinition.description.contains("L3") && knowledgeDefinition.description.contains("L4"))
    #expect(knowledgeDefinition.description.contains("depth defaults to 1"))
    #expect(knowledgeDefinition.description.contains("depth >= 2 is an indirect path"))
    #expect(!knowledgeDefinition.description.localizedCaseInsensitiveContains("must parse"))
    #expect(!knowledgeDefinition.description.localizedCaseInsensitiveContains("must read"))
    #expect(profileDefinition.description.contains("updated_at"))
    #expect(profileDefinition.description.contains("preferences, habits, traits, constraints, and interaction guidance"))
    #expect(!profileDefinition.description.localizedCaseInsensitiveContains("projects"))
    #expect(registry.permission(named: "memory_os_recent_context") == .readGraph)
    #expect(registry.permission(named: "memory_os_knowledge_context") == .readGraph)
    #expect(registry.permission(named: "memory_os_get_current_user_profile") == .readGraph)
    #expect(registry.definition(named: "memory_os_context") == nil)

    // Write tools and low-level primitives should NOT be registered
    #expect(registry.definition(named: "memory_os_l2_update_entities") == nil)
    #expect(registry.definition(named: "memory_os_update_current_user_profile") == nil)
    #expect(registry.definition(named: "memory_os_l2_find_entities") == nil)
    #expect(registry.definition(named: "memory_os_l4_find_entity") == nil)
    #expect(registry.definition(named: "memory_os_read_record") == nil)
}

private func memoryOSReadToolContext() -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run-memory-os-read", sessionID: "session", groupID: "group", userPrompt: "read memory", toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
}

private func temporaryAppMemoryOSReadToolDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-read-tool-\(UUID().uuidString).sqlite")
}
