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

private struct ApprovalAwareTool: AgentTool {
    let name = "approval_aware"
    let description = "Verifies that a policy-approved capability reaches tool execution."
    // Uses an ordinary write capability (not a hard human-gate like .sendMail) so it is
    // auto-approved under trustedWrite yet discoverable under readOnly/askToWrite.
    let permission: AgentPermissionCapability = .mutateCalendar
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard context.approvedCapabilities.contains(permission) else {
            throw AgentToolError.permissionDenied("Approved capability was not propagated")
        }
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "approved")
    }
}

private struct NetworkReadTool: AgentTool {
    let name = "web_search"
    let description = "Search the public web."
    let permission: AgentPermissionCapability = .externalNetwork
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "network")
    }
}

private struct DirectShellStub: AgentTool {
    let name = "Shell"
    let description = "Direct shell compatibility stub."
    let permission: AgentPermissionCapability = .runReadOnlyShellCommand
    let inputSchema = AgentToolInputSchema.closedObject(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "resolved")
    }
}

@Test func browserPermissionsSeparateReadingNavigationInteractionAndCommit() async {
    let readOnly = AgentPolicyEngine(permissionMode: .readOnly)
    #expect(await readOnly.evaluate(capability: .readBrowserPage, runID: "run", sessionID: "session").outcome == .approved)
    #expect(await readOnly.evaluate(capability: .navigateBrowser, runID: "run", sessionID: "session").outcome == .denied)

    let ask = AgentPolicyEngine(permissionMode: .askToWrite)
    #expect(await ask.evaluate(capability: .navigateBrowser, runID: "run", sessionID: "session").outcome == .approved)
    #expect(await ask.evaluate(capability: .interactBrowser, runID: "run", sessionID: "session").outcome == .needsApproval)

    let trusted = AgentPolicyEngine(permissionMode: .trustedWrite)
    #expect(await trusted.evaluate(capability: .interactBrowser, runID: "run", sessionID: "session").outcome == .approved)
    #expect(await trusted.evaluate(capability: .commitBrowserAction, runID: "run", sessionID: "session").outcome == .approved)
    #expect(await trusted.evaluate(capability: .transferBrowserFile, runID: "run", sessionID: "session").outcome == .approved)
}

@Test func executeAndAllowAllModesApproveEverySensitiveCapability() async {
    let capabilities: [AgentPermissionCapability] = [
        .mutatePersonality, .mutateContacts, .mutateCalendar,
        .commitBrowserAction, .transferBrowserFile, .deleteWorkspaceFile,
        .runNetworkShellCommand, .runDestructiveShellCommand
    ]
    for mode in [AgentPermissionMode.trustedWrite, .allowAll] {
        for capability in capabilities {
            let decision = await AgentPolicyEngine(permissionMode: mode).evaluate(
                capability: capability,
                runID: "run-execute",
                sessionID: "session-execute"
            )
            #expect(decision.outcome == .approved)
        }
    }

    // Sending mail is a hard human-gate capability: it requires approval even in
    // execute/allowAll modes (covered by interactiveWebPublishingAlwaysRequiresHumanApproval
    // for publishInteractiveWeb).
    for mode in [AgentPermissionMode.trustedWrite, .allowAll] {
        let send = await AgentPolicyEngine(permissionMode: mode).evaluate(
            capability: .sendMail,
            runID: "run-execute",
            sessionID: "session-execute",
            toolName: "mail_send_draft"
        )
        #expect(send.outcome == .needsApproval)
    }

    let askDecision = await AgentPolicyEngine(permissionMode: .askToWrite).evaluate(
        capability: .mutatePersonality,
        runID: "run-personality",
        sessionID: "session-personality",
        toolName: "personality_update"
    )
    #expect(askDecision.outcome == .approved)

    let readOnlyDecision = await AgentPolicyEngine(permissionMode: .readOnly).evaluate(
        capability: .mutatePersonality,
        runID: "run-personality-read-only",
        sessionID: "session-personality"
    )
    #expect(readOnlyDecision.outcome == .denied)
}

@Test func interactiveWebPublishingAlwaysRequiresHumanApproval() async {
    for mode in [AgentPermissionMode.askToWrite, .trustedWrite, .allowAll] {
        let decision = await AgentPolicyEngine(permissionMode: mode).evaluate(
            capability: .publishInteractiveWeb,
            runID: "run-publish",
            sessionID: "session-publish",
            toolName: "interactive_web_publish"
        )
        #expect(decision.outcome == .needsApproval)
    }

    let denied = await AgentPolicyEngine(permissionMode: .readOnly).evaluate(
        capability: .publishInteractiveWeb,
        runID: "run-publish",
        sessionID: "session-publish"
    )
    #expect(denied.outcome == .denied)
}

@Test func interactiveWebDraftUsesAppManagedDraftPermission() async {
    let readOnly = await AgentPolicyEngine(permissionMode: .readOnly).evaluate(
        capability: .createInteractiveWebDraft,
        runID: "run-draft-read-only",
        sessionID: "session-draft"
    )
    let askToWrite = await AgentPolicyEngine(permissionMode: .askToWrite).evaluate(
        capability: .createInteractiveWebDraft,
        runID: "run-draft-ask",
        sessionID: "session-draft"
    )

    #expect(readOnly.outcome == .denied)
    #expect(askToWrite.outcome == .approved)
}

@Test func toolRegistryResolvesCommonDirectWorkspaceToolAliases() async throws {
    var registry = AgentToolRegistry()
    registry.register(DirectShellStub())
    let context = AgentToolExecutionContext(
        runID: "run-shell-alias",
        sessionID: "session-shell-alias",
        groupID: "default",
        userPrompt: "inspect files",
        toolCallID: "call-shell-alias",
        policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
    )

    #expect(registry.definition(named: "shell")?.name == "Shell")
    #expect(registry.permission(named: "shell") == .runReadOnlyShellCommand)
    let result = try await registry.execute(
        AgentToolCall(id: "call-shell-alias", name: "shell", argumentsJSON: "{}"),
        context: context
    )
    #expect(result.toolName == "Shell")
    #expect(result.contentText == "resolved")
}

@Test func executeModePropagatesAutomaticApprovalIntoToolContext() async throws {
    var registry = AgentToolRegistry()
    registry.register(ApprovalAwareTool())
    let context = AgentToolExecutionContext(
        runID: "run-execute",
        sessionID: "session-execute",
        groupID: "default",
        userPrompt: "send",
        toolCallID: "call-execute",
        policyEngine: AgentPolicyEngine(permissionMode: .trustedWrite)
    )

    let result = try await registry.execute(
        AgentToolCall(id: "call-execute", name: "approval_aware", argumentsJSON: "{}"),
        context: context
    )

    #expect(result.contentText == "approved")
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

@Test func externalNetworkPermissionMatchesMandatoryWebResearchFallbackContract() async {
    let readOnlyDecision = await AgentPolicyEngine(permissionMode: .readOnly).evaluate(
        capability: .externalNetwork,
        runID: "run-web-read-only",
        sessionID: "session-web",
        toolName: "web_search",
        payloadJSON: #"{"query":"current information"}"#
    )
    let askToWriteDecision = await AgentPolicyEngine(permissionMode: .askToWrite).evaluate(
        capability: .externalNetwork,
        runID: "run-web-ask",
        sessionID: "session-web",
        toolName: "web_search",
        payloadJSON: #"{"query":"current information"}"#
    )
    let trustedDecision = await AgentPolicyEngine(permissionMode: .trustedWrite).evaluate(
        capability: .externalNetwork,
        runID: "run-web-trusted",
        sessionID: "session-web",
        toolName: "web_fetch",
        payloadJSON: #"{"url":"https://example.com"}"#
    )

    #expect(readOnlyDecision.outcome == .denied)
    #expect(askToWriteDecision.outcome == .approved)
    #expect(trustedDecision.outcome == .approved)
}

@Test func discoverableRegistryDefinitionsExcludeDeniedCapabilitiesWithoutWritingAuditEvents() async {
    var registry = AgentToolRegistry()
    registry.register(EchoTool())
    registry.register(ApprovalAwareTool())
    registry.register(NetworkReadTool())
    let audit = InMemoryAgentAuditLog()
    let policy = AgentPolicyEngine(permissionMode: .readOnly, auditLog: audit)

    let names = Set(await registry.definitions(availableUnder: policy).map(\.name))

    #expect(names == ["approval_aware", "echo"])
    #expect(!names.contains("web_search"))
    #expect(await audit.events.isEmpty)
}

@Test func discoverableRegistryDefinitionsIncludeCapabilitiesThatNeedApproval() async {
    var registry = AgentToolRegistry()
    registry.register(ApprovalAwareTool())
    let policy = AgentPolicyEngine(permissionMode: .askToWrite)

    let names = await registry.definitions(availableUnder: policy).map(\.name)

    #expect(names == ["approval_aware"])
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
        arguments: try AgentToolArguments(json: #"{"timeZone":"Asia/Shanghai"}"#),
        context: context
    )

    let contentJSON = try #require(result.contentJSON)
    let data = Data(contentJSON.utf8)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(result.toolName == "get_current_time")
    #expect(result.contentText.contains("Current time:"))
    #expect(object["timeZone"] as? String == "Asia/Shanghai")
    #expect(object["time_zone"] == nil)
    #expect(object["unixTimestamp"] as? Double == 1_781_976_000)
    let iso8601 = try #require(object["iso8601"] as? String)
    let preciseISO8601 = try #require(object["iso8601WithFractionalSeconds"] as? String)
    #expect(!iso8601.contains("."))
    #expect(preciseISO8601.contains("."))
    #expect(AgentToolTimestampParser.parse(iso8601) == fixedDate)
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
