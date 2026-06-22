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
    try store.upsert(belief: MemoryOSBelief(id: "belief-1", topic: "Prompt governance", statement: "L3 records require reusable cognitive structure.", confidence: 0.93, evidenceStatementIDs: ["stmt-1"], validAt: now, projectedAt: now))

    let tool = MemoryOSReadRecordTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"layer":"L3","recordID":"belief-1"}"#), context: memoryOSReadToolContext())

    let json = try #require(result.contentJSON)
    #expect(json.contains("belief-1"))
    #expect(json.contains("Prompt governance"))
    #expect(json.contains("stmt-1"))
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

    registry.registerMemoryOSTools(facade: facade)

    #expect(registry.definition(named: "memory_os_read_record") != nil)
    #expect(registry.definition(named: "memory_os_read_provenance") != nil)
    #expect(registry.permission(named: "memory_os_read_record") == .readGraph)
    #expect(registry.permission(named: "memory_os_read_provenance") == .readGraph)
}

private func memoryOSReadToolContext() -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run-memory-os-read", sessionID: "session", groupID: "group", userPrompt: "read memory", toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
}

private func temporaryAppMemoryOSReadToolDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-read-tool-\(UUID().uuidString).sqlite")
}
