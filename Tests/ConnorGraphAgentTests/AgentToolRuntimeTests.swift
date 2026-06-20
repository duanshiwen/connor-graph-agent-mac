import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphSearch

private struct EchoTool: AgentTool {
    let name = "echo"
    let description = "Echo test input."
    let permission: AgentPermissionCapability = .readSession
    let inputSchema = AgentToolInputSchema.object(properties: [
        "text": .string(description: "Text to echo")
    ], required: ["text"])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            id: "result-echo",
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: arguments.string("text") ?? "",
            contentJSON: nil,
            citations: []
        )
    }
}

@Test func toolRegistryExecutesRegisteredToolAndWritesAuditDecision() async throws {
    var registry = AgentToolRegistry()
    registry.register(EchoTool())
    let audit = InMemoryAgentAuditLog()
    let policy = AgentPolicyEngine(permissionMode: .allowAll, auditLog: audit)
    let context = AgentToolExecutionContext(
        runID: "run-1",
        sessionID: "session-1",
        groupID: "default",
        userPrompt: "say hi",
        toolCallID: "tool-call-1",
        policyEngine: policy
    )
    let call = AgentToolCall(id: "tool-call-1", name: "echo", argumentsJSON: #"{"text":"hello"}"#)

    let result = try await registry.execute(call, context: context)

    #expect(result.contentText == "hello")
    #expect(result.error == nil)
    #expect(await audit.events.count == 1)
    #expect(await audit.events.first?.decision?.outcome == .approved)
}

@Test func readOnlyPolicyRejectsGraphWriteCapability() async throws {
    let audit = InMemoryAgentAuditLog()
    let policy = AgentPolicyEngine(permissionMode: .readOnly, auditLog: audit)

    let decision = await policy.evaluate(
        capability: .proposeGraphWrite,
        runID: "run-1",
        sessionID: "session-1",
        toolName: "graph_propose_fact",
        payloadJSON: "{}"
    )

    #expect(decision.outcome == .denied)
    #expect(await audit.events.count == 1)
}

@Test func getCurrentTimeToolReturnsDeterministicTimeForRequestedTimeZone() async throws {
    let fixedDate = Date(timeIntervalSince1970: 1_781_976_000)
    let tool = GetCurrentTimeTool(now: fixedDate, defaultTimeZone: TimeZone(identifier: "UTC")!)
    let context = AgentToolExecutionContext(
        runID: "run-time",
        sessionID: "session-time",
        groupID: "default",
        userPrompt: "what time is it",
        toolCallID: "tool-call-time",
        policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
    )

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"time_zone":"Asia/Shanghai"}"#),
        context: context
    )

    let contentJSON = try #require(result.contentJSON)
    let data = Data(contentJSON.utf8)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(result.toolName == "get_current_time")
    #expect(result.contentText.contains("Current time:"))
    #expect(object["time_zone"] as? String == "Asia/Shanghai")
    #expect(object["unix_timestamp"] as? Double == 1_781_976_000)
}

@Test func graphSearchToolReturnsStructuredHitsWithCitations() async throws {
    let search = TestHybridSearchService(hits: [
        GraphSearchHit(ownerType: .entity, ownerID: "node-memory", title: "Memory", text: "Graph memory", score: 1.0, retrievalMethod: "test")
    ])
    let tool = GraphSearchTool(searchService: search)
    let audit = InMemoryAgentAuditLog()
    let policy = AgentPolicyEngine(permissionMode: .readOnly, auditLog: audit)
    let context = AgentToolExecutionContext(
        runID: "run-1",
        sessionID: "session-1",
        groupID: "default",
        userPrompt: "memory",
        toolCallID: "tool-call-1",
        policyEngine: policy
    )

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"query":"memory","limit":5}"#),
        context: context
    )

    #expect(result.toolName == "graph_search")
    #expect(result.citations == ["entity:node-memory"])
    #expect(result.contentText.contains("Memory"))
    #expect(result.contentJSON?.contains("node-memory") == true)
}
