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
    #expect(tool.description.contains("updated_at"))
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Connor Memory OS retrieval","layers":["L1","L2"],"limit":5}"#), context: memoryOSToolContext())

    let json = try #require(result.contentJSON)
    #expect(result.toolName == "memory_os_search")
    #expect(result.contentText.contains("Memory OS search returned"))
    #expect(json.contains("\"layer\":\"L1\"") || json.contains("\"layer\":\"L2\""))
    #expect(json.contains("Connor Memory OS"))
}

@Test func memoryOSRecentAndKnowledgeContextToolsReturnDifferentSemantics() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 12_000)
    try store.upsert(node: MemoryOSNode(id: "memory-os-node", stableKey: "system:connor-memory-os-current", nodeType: "project", name: "Connor Memory OS"))
    try store.upsert(statement: MemoryOSStatement(id: "current-status", subjectID: "memory-os-node", predicate: "status", text: "Connor Memory OS is currently splitting retrieval tools.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: []))
    try store.upsert(belief: MemoryOSBelief(id: "knowledge-rule", statement: "Connor Memory OS separates operational state from reusable knowledge.", domain: "knowledge", relatedObjectNames: "Connor Memory OS", createdAt: now, updatedAt: now))
    try store.upsert(entity: MemoryOSEntity(id: "entity-memory-os", stableKey: "system:connor-memory-os", entityType: "system", name: "Connor Memory OS", summary: "Background memory infrastructure", confidence: 0.95))
    try store.upsert(entity: MemoryOSEntity(id: "entity-l4", stableKey: "layer:l4", entityType: "memory_layer", name: "L4 Stable Entity Layer", summary: "Stores stable entities and concepts", confidence: 0.95))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-l4", entityID: "entity-memory-os", predicate: .hasPart, objectEntityID: "entity-l4", text: "Connor Memory OS contains L4 Stable Entity Layer.", assertionKind: .summarized, confidence: 0.92, validAt: now, committedAt: now, evidenceSpanIDs: []))

    let recentResult = try await MemoryOSRecentContextTool(facade: facade).execute(arguments: AgentToolArguments(json: #"{"query":"Connor Memory OS；retrieval tools"}"#), context: memoryOSToolContext())
    let knowledgeResult = try await MemoryOSKnowledgeContextTool(facade: facade).execute(arguments: AgentToolArguments(json: #"{"query":"Connor Memory OS;reusable knowledge"}"#), context: memoryOSToolContext())

    #expect(recentResult.toolName == "memory_os_recent_context")
    let recentPayload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(recentResult.contentJSON).utf8))
    #expect(recentPayload.records.contains { $0.text.contains("currently splitting retrieval tools") })
    #expect(!recentPayload.records.contains { $0.text.contains("reusable knowledge") })
    #expect(recentPayload.records.allSatisfy { !$0.recordID.isEmpty && ["L1", "L2"].contains($0.layer) })

    #expect(knowledgeResult.toolName == "memory_os_knowledge_context")
    let knowledgePayload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(knowledgeResult.contentJSON).utf8))
    #expect(knowledgePayload.records.contains { $0.text.contains("reusable knowledge") })
    #expect(knowledgePayload.records.contains { $0.text.contains("L4 Stable Entity Layer") })
    #expect(!knowledgePayload.records.contains { $0.text.contains("currently splitting retrieval tools") })
}

@Test func memoryOSRecentContextToolAcceptsMixedLLMQuerySeparators() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 12_100)
    try store.upsert(node: MemoryOSNode(id: "annie-node", stableKey: "person:annie", nodeType: "person", name: "Annie"))
    try store.upsert(statement: MemoryOSStatement(
        id: "annie-memory",
        subjectID: "annie-node",
        predicate: "received",
        text: "Annie received the product invitation.",
        confidence: 0.9,
        validAt: now,
        committedAt: now,
        evidenceSpanIDs: []
    ))

    let result = try await MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store)).execute(
        arguments: AgentToolArguments(json: #"{"query":"Annie,朋友|friend"}"#),
        context: memoryOSToolContext()
    )
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(result.contentJSON).utf8))

    #expect(payload.query == "Annie 朋友 friend")
    #expect(payload.records.contains { $0.text.contains("Annie received the product invitation") })
}

@Test func memoryOSContextToolsSupportEmptyQueryTimeRangeRetrieval() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let rangeStart = Date(timeIntervalSince1970: 20_000)
    let rangeEnd = Date(timeIntervalSince1970: 30_000)
    let node = MemoryOSNode(id: "time-range-node", stableKey: "time-range-node", nodeType: "project", name: "Time Range")
    try store.upsert(node: node)
    try store.upsert(statement: MemoryOSStatement(id: "inside-range", subjectID: node.id, predicate: "status", text: "Included period record", confidence: 0.9, validAt: rangeStart.addingTimeInterval(100), committedAt: rangeStart.addingTimeInterval(100)))
    try store.upsert(statement: MemoryOSStatement(id: "outside-range", subjectID: node.id, predicate: "status", text: "Excluded period record", confidence: 0.9, validAt: rangeStart.addingTimeInterval(-100), committedAt: rangeStart.addingTimeInterval(-100)))
    let arguments = try AgentToolArguments(json: """
    {"query":"","startDate":"\(iso8601(rangeStart))","endDate":"\(iso8601(rangeEnd))"}
    """)

    let result = try await MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store)).execute(arguments: arguments, context: memoryOSToolContext())
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(result.contentJSON).utf8))

    #expect(payload.query.isEmpty)
    #expect(payload.records.contains { $0.recordID == "inside-range" })
    #expect(!payload.records.contains { $0.recordID == "outside-range" })

    let focusedResult = try await MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store)).execute(
        arguments: try AgentToolArguments(json: """
        {"query":"period","startDate":"\(iso8601(rangeStart))","endDate":"\(iso8601(rangeEnd))"}
        """),
        context: memoryOSToolContext()
    )
    let focusedPayload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(focusedResult.contentJSON).utf8))
    #expect(focusedPayload.records.contains { $0.recordID == "inside-range" })
    #expect(!focusedPayload.records.contains { $0.recordID == "outside-range" })
}

@Test func memoryOSContextToolsRequireTimeBoundsWhenQueryIsEmpty() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let tool = MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store))

    await #expect(throws: AgentToolError.self) {
        try await tool.execute(arguments: AgentToolArguments(json: #"{"query":""}"#), context: memoryOSToolContext())
    }
}

@Test func memoryOSRecentContextLimitExpansionReturnsOnlyIncrementalRecords() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 13_000)
    for index in 0..<35 {
        let nodeID = "incremental-node-\(index)"
        try store.upsert(node: MemoryOSNode(id: nodeID, stableKey: nodeID, nodeType: "project", name: "Incremental Project \(index)"))
        try store.upsert(statement: MemoryOSStatement(id: "incremental-statement-\(index)", subjectID: nodeID, predicate: "status", text: "Incremental memory result \(index).", confidence: 0.9, validAt: now.addingTimeInterval(Double(index)), committedAt: now.addingTimeInterval(Double(index)), evidenceSpanIDs: []))
    }
    let tool = MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store))
    let context = memoryOSToolContext()

    let first = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Incremental memory","limit":10}"#), context: context)
    let expanded = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Incremental memory","limit":30}"#), context: context)
    let firstPayload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(first.contentJSON).utf8))
    let expandedPayload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(expanded.contentJSON).utf8))

    #expect(firstPayload.requestedLimit == 10)
    #expect(firstPayload.returnedCount == 10)
    #expect(expandedPayload.requestedLimit == 30)
    #expect(expandedPayload.returnedCount == 20)
    #expect(expandedPayload.cumulativeReturnedCount == 30)
    #expect(Set(firstPayload.records.map(\.recordID)).isDisjoint(with: Set(expandedPayload.records.map(\.recordID))))
    #expect(firstPayload.hasMore == true)
    #expect(!firstPayload.partial && !expandedPayload.partial)
}

@Test func memoryOSContextToolsClampLimitAndDepthFromConfiguration() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let config = MemoryOSContextToolConfiguration(minimumResultLimit: 12, defaultResultLimit: 15, maxDepth: 4)
    let tool = MemoryOSKnowledgeContextTool(facade: AppMemoryOSFacade(store: store), configuration: config)
    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"missing memory","limit":1,"depth":99}"#), context: memoryOSToolContext())
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(result.contentJSON).utf8))
    #expect(payload.requestedLimit == 12)
    #expect(payload.returnedCount == 0)
    #expect(payload.hasMore == nil)
    #expect(!payload.partial)
}

@Test func memoryOSContextCapacityDropsWholeRecordsAndMarksPartial() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSRetrievalToolDatabaseURL().path)
    try store.migrate()
    let node = MemoryOSNode(id: "capacity-node", stableKey: "capacity-node", nodeType: "project", name: "Capacity")
    try store.upsert(node: node)
    try store.upsert(statement: MemoryOSStatement(id: "capacity-record", subjectID: node.id, predicate: "detail", text: "Capacity " + String(repeating: "complete-record-content ", count: 200), confidence: 0.9, evidenceSpanIDs: []))
    let config = MemoryOSContextToolConfiguration(maxResponseCharacters: 1_024)
    let tool = MemoryOSRecentContextTool(facade: AppMemoryOSFacade(store: store), configuration: config)

    let result = try await tool.execute(arguments: AgentToolArguments(json: #"{"query":"Capacity complete record"}"#), context: memoryOSToolContext())
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(try #require(result.contentJSON).utf8))

    #expect(payload.records.isEmpty)
    #expect(payload.partial)
    #expect(payload.hasMore == true)
    #expect(!result.contentText.contains("complete-record-content"))
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
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(json.utf8))
    #expect(result.toolName == "memory_os_get_current_user_profile")
    #expect(payload.query == "current_user profile")
    #expect(payload.records.contains { $0.text.contains("structured architectural explanations") && $0.updatedAt == iso8601(now) })
    #expect(payload.records.contains { $0.text.contains("phase-by-phase execution updates") && $0.updatedAt == iso8601(now) })
    #expect(Set(result.citations) == Set(payload.records.map(\.recordID)))
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
    let payload = try JSONDecoder().decode(MemoryOSContextToolResponse.self, from: Data(json.utf8))
    #expect(result.toolName == "memory_os_get_current_user_profile")
    #expect(payload.records.isEmpty)
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
