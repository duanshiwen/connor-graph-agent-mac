import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphSearch

private struct Train4HybridSearchService: GraphHybridSearchService, Sendable {
    var response: GraphSearchResponse
    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse { response }
}

private struct Train4FailingHybridSearchService: GraphHybridSearchService, Sendable {
    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse { throw AgentContextBuilderError.asyncContextRequired }
}

private actor Train4CapturingProvider: AgentModelProvider {
    let modelID = "train4-capturing"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private(set) var lastRequest: AgentModelRequest?

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        lastRequest = request
        return AgentModelResponse(text: "Memory-aware answer", usage: AgentModelUsage(promptTokens: 10, completionTokens: 4))
    }
}

@Test func commercialTrain4ContextBuilderBuildsMemoryContextContractWithRoles() async throws {
    let service = Train4HybridSearchService(response: GraphSearchResponse(hits: [
        GraphSearchHit(ownerType: .episode, ownerID: "episode-pref", title: "Preference", text: "诗闻偏好结构化推进。", score: 0.93, retrievalMethod: "hybrid", sourceEpisodeIDs: ["episode-pref"], metadata: ["candidate_kind": "preference"]),
        GraphSearchHit(ownerType: .statement, ownerID: "fact-decision", title: "DECIDED", text: "Train 4 决定让 Graph Memory 进入 Agent core runtime。", score: 0.88, retrievalMethod: "graph", sourceEpisodeIDs: ["episode-decision"], metadata: ["memory_role": "decision"]),
        GraphSearchHit(ownerType: .entity, ownerID: "project-connor", title: "Connor", text: "Graph memory native Agent OS。", score: 0.77, retrievalMethod: "fts", metadata: ["entity_kind": "work_object"])
    ]))
    let builder = AgentContextBuilder(hybridSearchService: service, groupID: "default", limit: 5)

    let contract = try await builder.memoryContextContract(for: "Graph Memory 怎么进入 Agent 核心？", sessionID: "session-1", runID: "run-1")

    #expect(contract.items.map(\.role) == [.preference, .decision, .projectState])
    #expect(contract.retrievalMetrics.itemCount == 3)
    #expect(contract.retrievalMetrics.evidenceEpisodeCount == 2)
    #expect(contract.summary.contains("preference=1"))
    #expect(contract.agentContext.renderedText.contains("memory role preference"))
}

@Test func agentLoopAppendsUserBasicInfoToProviderSystemMessage() async throws {
    let provider = Train4CapturingProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: AgentLoopConfiguration(
            instructionAppendix: "## 用户基本信息\n- 称呼：段诗闻\n- 备注：我喜欢橙色"
        )
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-user-info", userMessage: "我叫什么？我喜欢什么颜色？")) {
        events.append(event)
    }

    let request = try #require(await provider.lastRequest)
    let systemMessage = try #require(request.messages.first(where: { $0.role == .system }))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(systemMessage.content.contains("You are 康纳同学 (Connor), a personal AI assistant for everyday work and life."))
    #expect(systemMessage.content.contains("## 用户基本信息"))
    #expect(systemMessage.content.contains("- 称呼：段诗闻"))
    #expect(systemMessage.content.contains("- 备注：我喜欢橙色"))
}

@Test func commercialTrain4AgentLoopGracefullyDegradesWhenMemoryContextFails() async throws {
    let provider = Train4CapturingProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        contextBuilder: AgentContextBuilder(hybridSearchService: Train4FailingHybridSearchService(), groupID: "default")
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-1", userMessage: "继续")) {
        events.append(event)
    }

    let request = await provider.lastRequest
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(request?.messages.contains(where: { $0.content.contains("Relevant Graph Memory Context") }) == false)
}

@Test func commercialTrain4ReadinessUsesCoreGraphMemoryEvidence() {
    let readiness = CommercialGraphMemoryReadiness.ready(
        pendingCandidateCount: 1,
        openHoldCount: 0,
        recentChangeCount: 2,
        contextReady: true,
        ingestionReady: true,
        distillationReady: true,
        reviewReady: true,
        contextItemCount: 3,
        stagedBundleCount: 2,
        distillationCandidateCount: 1,
        feedbackSignalCount: 1
    )
    let input = CommercialReadinessInput(
        sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 1, labelDefinitionCount: 1, artifactDirectoriesReady: true),
        modelProvider: .ready(providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, modelID: "claude-sonnet-4-5", healthStatus: "ready"),
        extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
        graphMemory: readiness,
        nativeUI: .ready(shellItemCount: 1, commandCount: 1, settingsPanelsReady: true)
    )

    let card = CommercialReadinessGate().evaluate(input).cards.first { $0.phase == .graphMemoryLoop }

    #expect(card?.status == .ready)
    #expect(card?.metrics["contextReady"] == "true")
    #expect(card?.metrics["contextItems"] == "3")
    #expect(card?.metrics["feedbackSignals"] == "1")
}
