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

@Test func bootstrapQueryPlannerDoesNotUseAChineseQuestionAsOneFTSPhrase() {
    let request = AgentChatRequest(
        sessionID: "session",
        userMessage: "为什么你不能查询历史记录？查询记忆系统？为什么？是有什么限制吗？"
    )

    let query = AssistantBootstrapQueryPlanner().query(for: request)

    #expect(query.contains("历史记录"))
    #expect(query.contains("记忆系统"))
    #expect(!query.contains("为什么你不能查询历史记录"))
    #expect(query.count <= 240)
}

@Test func bootstrapQueryPlannerCarriesForwardAReferencedConversationEntity() {
    let request = AgentChatRequest(
        sessionID: "session",
        userMessage: "我想以康纳同学的身份给她写一封邮件，跟小小分享这段旅程。",
        recentMessages: [
            AgentMessage(role: .user, content: "这就是我们讨论过的小小基金。"),
            AgentMessage(role: .assistant, content: "确认是 **小小基金（XIAOXIAO FUND）**。")
        ]
    )

    let query = AssistantBootstrapQueryPlanner().query(for: request)

    #expect(query.contains("康纳同学"))
    #expect(query.contains("小小基金"))
    #expect(query.contains("XIAOXIAO FUND"))
}

@Test func bootstrapQueryPlannerKeepsTechnicalNamesWithoutNarrativeNoise() {
    let request = AgentChatRequest(
        sessionID: "session",
        userMessage: "Please investigate why Memory OS and GPT-5.6 failed in the Agent bootstrap."
    )

    let query = AssistantBootstrapQueryPlanner().query(for: request)

    #expect(query.contains("Memory OS"))
    #expect(query.contains("GPT-5.6"))
    #expect(query.contains("Agent"))
    #expect(!query.contains("Please investigate"))
}

@Test func bootstrapRenderDistinguishesAnEmptySuccessfulReadFromPermissionFailure() {
    let report = AssistantBootstrapReport(
        contextPack: AssistantContextPack(failures: ["note_search: denied"]),
        query: "小小基金;XIAOXIAO FUND",
        attemptedToolNames: ["memory_os_recent_context", "note_search"],
        succeededToolNames: ["memory_os_recent_context"]
    )

    let rendered = AssistantEvidenceReducer().render(report)

    #expect(rendered.contains("memory_os_recent_context: succeeded"))
    #expect(rendered.contains("note_search: failed"))
    #expect(rendered.contains("completed with zero matches"))
    #expect(rendered.contains("小小基金;XIAOXIAO FUND"))
}

@Test func evidenceReducerReadsMemoryToolSnakeCaseMetadata() throws {
    let output = AssistantBootstrapToolOutput(
        name: "memory_os_recent_context",
        payload: #"{"records":[{"record_id":"memory-1","text":"Relevant memory","occurred_at":"2026-08-03T05:42:38Z","retrieval_score":0.75}]}"#,
        error: nil
    )

    let item = try #require(AssistantEvidenceReducer().reduce([output]).recentMemory.first)

    #expect(item.id == "memory-1")
    #expect(item.relevance == 0.75)
    #expect(item.occurredAt != nil)
}
