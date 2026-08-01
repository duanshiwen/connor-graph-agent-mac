import Testing
@testable import ConnorGraphAgent
import ConnorGraphCore

private struct BootstrapFixtureTool: AgentTool {
    let name: String
    let payload: String
    let description = "bootstrap fixture"
    let permission: AgentPermissionCapability = .readGraph
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: payload, contentJSON: payload)
    }
}

@Test func bootstrapExecutesEveryAvailableMandatoryReadExactlyOnce() async {
    var registry = AgentToolRegistry()
    for name in AssistantBootstrapCoordinator.internalToolNames {
        registry.register(BootstrapFixtureTool(
            name: name,
            payload: #"{"records":[{"recordID":"one","text":"useful evidence"}]}"#
        ))
    }
    let request = AgentChatRequest(runID: "run", sessionID: "session", userMessage: "prepare report")

    let report = await AssistantBootstrapCoordinator().run(
        request: request,
        registry: registry,
        policy: AgentPolicyEngine(permissionMode: .readOnly)
    )

    #expect(report.attemptedToolNames == AssistantBootstrapCoordinator.internalToolNames)
    #expect(report.succeededToolNames == AssistantBootstrapCoordinator.internalToolNames)
    #expect(report.contextPack.recentMemory.count == 1)
    #expect(report.contextPack.durableKnowledge.count == 1)
    #expect(report.contextPack.userProfile.count == 1)
    #expect(report.contextPack.noteCandidates.count == 1)
}

@Test func evidenceReducerCapsProfileAndRenderedContextBudget() {
    let records = (0..<100).map { index in
        let text = String(repeating: "x", count: 400)
        return "{\"recordID\":\"profile-\(index)\",\"text\":\"\(text)\"}"
    }.joined(separator: ",")
    let output = AssistantBootstrapToolOutput(
        name: "memory_os_get_current_user_profile",
        payload: "{\"records\":[\(records)]}",
        error: nil
    )
    let configuration = AssistantBootstrapConfiguration(
        profileLimit: 10,
        maximumItemCharacters: 100,
        maximumContextTokens: 500
    )
    let reducer = AssistantEvidenceReducer(configuration: configuration)

    let pack = reducer.reduce([output])
    let rendered = reducer.render(pack)

    #expect(pack.userProfile.count <= 10)
    #expect(AgentPromptBudgetEstimator().estimate(rendered).estimatedTokenCount <= 500)
}
