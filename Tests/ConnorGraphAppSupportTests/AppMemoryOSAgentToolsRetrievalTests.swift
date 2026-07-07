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

@Test func memoryOSContextToolReturnsFlatStringArray() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 12_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-memory-os", stableKey: "system:connor-memory-os", entityType: "system", name: "Connor Memory OS", summary: "Background memory infrastructure", confidence: 0.95))
    try store.upsert(entity: MemoryOSEntity(id: "entity-l4", stableKey: "layer:l4", entityType: "memory_layer", name: "L4 Stable Entity / Concept Layer", summary: "Stores stable entities and concepts", confidence: 0.95))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-l4", entityID: "entity-memory-os", predicate: .hasPart, objectEntityID: "entity-l4", text: "Connor Memory OS contains L4 Stable Entity / Concept Layer.", assertionKind: .summarized, confidence: 0.92, validAt: now, committedAt: now, evidenceSpanIDs: []))

    let tool = MemoryOSContextTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Connor Memory OS;L4"}"#), context: memoryOSToolContext())

    #expect(result.toolName == "memory_os_context")
    #expect(result.contentText.contains("item(s) for"))
    #expect(result.contentText.contains("search term"))

    let contentJSON = try #require(result.contentJSON)
    let items = try JSONDecoder().decode([String].self, from: Data(contentJSON.utf8))
    #expect(!items.isEmpty)
    #expect(items.contains { $0.contains("Connor Memory OS") })
}

@Test func memoryOSGetCurrentUserProfileToolAggregatesCurrentUserHitsWithoutNameCoupling() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    let user = MemoryOSEntity(id: "person-current", stableKey: "current_user", entityType: "person", name: "Current User", aliases: ["primary user"], createdAt: now, updatedAt: now, metadata: ["role": "current_user"])
    try store.upsert(entity: user)
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "l4-user-pref-1", entityID: user.id, predicate: .relatedTo, text: "current_user prefers structured architectural explanations.", confidence: 0.92, validAt: now, committedAt: now, evidenceSpanIDs: ["span-user-1"]))
    try store.upsert(node: MemoryOSNode(id: "node-current-user", stableKey: "current_user_profile", nodeType: "person_profile", name: "current_user profile"))
    try store.upsert(statement: MemoryOSStatement(id: "stmt-user-1", subjectID: "node-current-user", predicate: "has_preference", text: "current_user prefers concise phase-by-phase execution updates.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span-user-2"]))

    let tool = MemoryOSGetCurrentUserProfileTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    let lines = try JSONDecoder().decode([String].self, from: Data(json.utf8))
    #expect(result.toolName == "memory_os_get_current_user_profile")
    #expect(result.contentText.contains("current_user profile"))
    #expect(lines.contains { $0.contains("structured architectural explanations") })
    #expect(lines.contains { $0.contains("structured architectural explanations") && $0.contains("(updated_at: \(iso8601(now)))") })
    #expect(lines.contains { $0.contains("phase-by-phase execution updates") })
    #expect(lines.contains { $0.contains("phase-by-phase execution updates") && $0.contains("(updated_at: \(iso8601(now)))") })
    #expect(!json.contains("shiwen"))
}

@Test func memoryOSBootstrapEnsuresCurrentUserAnchorWithoutGenericAliases() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)

    let anchor = try facade.ensureCurrentUserAnchor(now: Date(timeIntervalSince1970: 10_000))

    #expect(anchor.stableKey == "current_user")
    #expect(anchor.entityType == "person")
    #expect(anchor.metadata["person_role"] == "current_user")
    #expect(anchor.metadata["protected_identity_anchor"] == "true")
    let forbidden = Set(["user", "users", "用户", "当前用户", "current", "profile", "current user", "current_user"])
    #expect(anchor.aliases.allSatisfy { !forbidden.contains($0.lowercased()) })
}

@Test func memoryOSGetCurrentUserProfileDoesNotReturnGenericUserConcepts() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    let genericUser = MemoryOSEntity(
        id: "wikidata-user",
        stableKey: "wikidata:Q278368",
        entityType: "concept",
        name: "用户",
        aliases: ["user", "profile user"],
        summary: "使用电脑或网络服务的人",
        confidence: 0.95,
        createdAt: now,
        updatedAt: now,
        metadata: ["source": "foundation_kg"]
    )
    try store.upsert(entity: genericUser)
    try store.upsert(entityStatement: MemoryOSEntityStatement(
        id: "generic-user-stmt",
        entityID: genericUser.id,
        predicate: .subclassOf,
        text: "communication user -- P279 --> 消费者",
        confidence: 0.9,
        validAt: now,
        committedAt: now,
        evidenceSpanIDs: []
    ))

    let tool = MemoryOSGetCurrentUserProfileTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    let lines = try JSONDecoder().decode([String].self, from: Data(json.utf8))
    #expect(result.toolName == "memory_os_get_current_user_profile")
    #expect(lines.isEmpty)
    #expect(!json.contains("wikidata-user"))
    #expect(!json.contains("communication user"))
    #expect(!json.contains("使用电脑或网络服务的人"))
}

@Test func memoryOSUpdateCurrentUserProfileWritesMinimalCurrentUserFact() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let tool = MemoryOSUpdateCurrentUserProfileTool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"""
    {
      "facts": [
        {
          "statement": "Current user prefers mature systemic plans over minimal patches for architectural issues.",
          "factType": "profile_preference",
          "relation": "PREFERS"
        }
      ],
      "sessionID": "session"
    }
    """#), context: memoryOSToolContext())

    let payload = try memoryOSToolJSON(result)
    #expect(result.toolName == "memory_os_update_current_user_profile")
    #expect(payload["accepted"] as? Bool == true)
    #expect(payload["currentUserEntityID"] as? String != nil)
    #expect(payload["scopePolicy"] as? String == "append_only_current_user_fact_anchor")
    let statementIDs = try #require(payload["statementIDs"] as? [String])
    #expect(statementIDs.count == 1)

    let profile = try facade.currentUserProfileContext()
    #expect(!profile.isEmpty)
    #expect(profile.contains { $0.contains("Current user prefers mature systemic plans over minimal patches for architectural issues.") && $0.contains("(updated_at:") })
}

@Test func memoryOSUpdateCurrentUserProfileRejectsExtraFactFields() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let tool = MemoryOSUpdateCurrentUserProfileTool(facade: facade)

    await #expect(throws: Error.self) {
        try await tool.execute(arguments: AgentToolArguments(json: #"""
        {
          "facts": [
            {
              "statement": "Current user prefers structured answers.",
              "factType": "profile_preference",
              "relation": "PREFERS",
              "evidence": "not accepted"
            }
          ]
        }
        """#), context: memoryOSToolContext())
    }
}

@Test func memoryOSUpdateCurrentUserProfileRejectsInvalidFactTypeAndRelation() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let tool = MemoryOSUpdateCurrentUserProfileTool(facade: facade)

    await #expect(throws: Error.self) {
        try await tool.execute(arguments: AgentToolArguments(json: #"""
        {
          "facts": [
            {
              "statement": "Current user prefers structured answers.",
              "factType": "random_type",
              "relation": "PREFERS"
            }
          ]
        }
        """#), context: memoryOSToolContext())
    }

    await #expect(throws: Error.self) {
        try await tool.execute(arguments: AgentToolArguments(json: #"""
        {
          "facts": [
            {
              "statement": "Current user prefers structured answers.",
              "factType": "profile_preference",
              "relation": "UNKNOWN_RELATION"
            }
          ]
        }
        """#), context: memoryOSToolContext())
    }
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
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "l4-stmt-1", entityID: entityA.id, predicate: .relatedTo, objectEntityID: entityB.id, text: "供需弹性关联价格变化。", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"]))

    let tool = MemoryOSExpandL4Tool(facade: facade)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"entityName":"供需弹性","depth":1,"limit":10}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_expand_l4")
    #expect(result.contentText.contains("L4 expansion returned"))
    #expect(json.contains("l4-stmt-1"))
    #expect(json.contains("entity-b"))
}

private func memoryOSToolJSON(_ result: AgentToolResult) throws -> [String: Any] {
    let contentJSON = try #require(result.contentJSON)
    return try #require(JSONSerialization.jsonObject(with: Data(contentJSON.utf8)) as? [String: Any])
}

private func memoryOSToolContext() -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run-memory-os-retrieval", sessionID: "session", groupID: "group", userPrompt: "search memory", toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func temporaryAppMemoryOSRetrievalToolDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-retrieval-tool-\(UUID().uuidString).sqlite")
}
