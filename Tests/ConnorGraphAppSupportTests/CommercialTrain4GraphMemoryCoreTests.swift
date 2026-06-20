import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphMemory
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
    #expect(systemMessage.content.contains("You are Connor, a general-purpose local AI assistant."))
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

@Test func commercialTrain4FeedbackSignalsAreDerivedFromMemoryIngestionTriggers() {
    var buffer = MemoryStagingBuffer(sessionID: "session-1")
    buffer.append(ConversationTurnBundle(
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "u1", role: .user, content: "请记住我偏好结构化推进。")],
        assistantMessage: ConversationTurnMessage(id: "a1", role: .assistant, content: "已记录。"),
        status: .closed
    ))
    let result = MemoryIngestionResult(buffer: buffer, appendedBundleIDs: ["bundle-1"], triggerReasons: [.explicitRememberRequest, .highValueSignal])

    let signals = AgentGraphMemoryFeedbackSignal.signals(from: result, runID: "run-1", sessionID: "session-1")

    #expect(signals.map(\.trigger) == [.explicitRemember, .highValueSignal])
    #expect(signals.first?.explicitRemember == true)
    #expect(signals.last?.highValue == true)
    #expect(signals.first?.importance == 0.95)
}

@Test func commercialTrain4GraphMemoryDashboardShowsCoreMemorySurface() async throws {
    let context = AgentGraphMemoryContextContract(
        query: "偏好",
        sessionID: "session-1",
        runID: "run-1",
        groupID: "default",
        items: [AgentGraphMemoryContextItem(sourceID: "episode:pref", kind: .observeLog, role: .preference, content: "诗闻偏好结构化推进。", reason: "matched via hybrid", scoreLabel: "93%")],
        summary: "1 item"
    )
    let signal = AgentGraphMemoryFeedbackSignal(sessionID: "session-1", trigger: .explicitRemember, candidateKind: "preference", importance: 0.95, confidence: 0.8, rationale: "explicit remember")
    var buffer = MemoryStagingBuffer(sessionID: "session-1")
    buffer.append(ConversationTurnBundle(sessionID: "session-1", userMessages: [ConversationTurnMessage(role: .user, content: "请记住这个偏好")]))
    let distillation = MemoryDistillationResult(
        sessionID: "session-1",
        sourceBufferID: buffer.id,
        preferenceCandidates: [MemoryDistillationCandidate(kind: .preference, title: "Preference", content: "结构化推进", rationale: "preference", importance: 0.9, confidence: 0.8)]
    )

    let dashboard = GraphMemoryProductizationCenter.dashboard(contextContract: context, feedbackSignals: [signal], stagingBuffer: buffer, distillationResult: distillation)

    #expect(dashboard.summary.contextReady == true)
    #expect(dashboard.summary.ingestionReady == true)
    #expect(dashboard.summary.distillationReady == true)
    #expect(dashboard.summary.contextItemCount == 1)
    #expect(dashboard.summary.feedbackSignalCount == 1)
    #expect(dashboard.summary.distillationCandidateCount == 1)
    #expect(dashboard.cards.map(\.kind).contains(.contextUse))
    #expect(dashboard.cards.map(\.kind).contains(.feedbackSignal))
    #expect(dashboard.cards.map(\.kind).contains(.distillationCandidate))
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
