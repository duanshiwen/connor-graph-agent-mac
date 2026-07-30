import Foundation
import Testing
import ConnorGraphAgent

private struct PhasedTestKnowledgeSource: AgentExternalKnowledgeSource {
    let id: String
    let kind: AgentExternalKnowledgeSourceKind
    let isReadOnly = true
    let delay: UInt64

    func search(_ request: AgentExternalResearchRequest) async throws -> [AgentExternalKnowledgeItem] {
        try await Task.sleep(nanoseconds: delay)
        return [.init(id: request.id, sourceID: id, uri: "https://example.com/\(request.query)", title: request.query, summary: "summary \(request.query)", selectedContent: "search body must be removed")]
    }

    func read(_ request: AgentExternalResearchReadRequest) async throws -> AgentExternalKnowledgeItem {
        try await Task.sleep(nanoseconds: delay)
        return .init(id: request.id, sourceID: id, uri: request.uri, title: request.uri, summary: "read", selectedContent: "original \(request.uri)")
    }
}

private actor PhasedTestMemoryProvider: AgentMemoryQueryProvider {
    private(set) var partitions: [AgentMemoryPartition] = []

    func query(_ request: AgentMemoryQueryRequest, partition: AgentMemoryPartition) async throws -> AgentMemoryPartitionPage {
        partitions.append(partition)
        switch partition {
        case .recent:
            return .init(items: [
                .init(id: "shared", text: "recent wins", eventTime: Date(timeIntervalSince1970: 30), provenance: "recent"),
                .init(id: "recent", text: "recent", eventTime: Date(timeIntervalSince1970: 20), provenance: "recent")
            ], nextCursor: "r2")
        case .longTerm:
            return .init(items: [
                .init(id: "old", text: "old", eventTime: Date(timeIntervalSince1970: 10), provenance: "long"),
                .init(id: "shared", text: "duplicate", eventTime: Date(timeIntervalSince1970: 5), provenance: "long")
            ], nextCursor: "l2")
        }
    }

    func observedPartitions() -> [AgentMemoryPartition] { partitions }
}

private actor PhasedLoopModelProvider: AgentModelProvider {
    let modelID = "phased-loop-test"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: true, supportsStructuredOutput: true, supportsVision: false)
    private var responses: [AgentModelResponse]
    private(set) var requests: [AgentModelRequest] = []

    init(responses: [AgentModelResponse]) { self.responses = responses }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        return responses.removeFirst()
    }

    func capturedRequests() -> [AgentModelRequest] { requests }
}

private struct PhasedLoopMemoryTool: AgentTool {
    let name: String
    let permission: AgentPermissionCapability = .readGraph
    let description = "test memory"
    let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: ""), "page": .integer(description: ""), "pageSize": .integer(description: ""),
        "purpose": .string(description: ""), "view": .string(description: ""), "depth": .integer(description: "")
    ], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let json = name == AgentContinuityPreflightPolicy.currentUserProfileToolName
            ? #"{"success":true,"records":[],"nextPage":null}"#
            : #"{"success":true,"records":[],"nextPage":null}"#
        return AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: json, contentJSON: json)
    }
}

@Test func promptModuleCatalogHasCompleteStableAcyclicClassification() {
    #expect(AgentPromptModuleCatalog.specifications.count == 42)
    #expect(AgentPromptModuleCatalog.duplicateIDs.isEmpty)
    #expect(AgentPromptModuleCatalog.dependencyCycles.isEmpty)
    #expect(Set(AgentPromptModuleCatalog.specifications.map(\.loadingPolicy)) == [.kernel, .eagerWhenRequired, .onDemand])
    #expect(AgentPromptModuleCatalog.specifications.allSatisfy { !$0.summary.isEmpty })

    let activated = AgentPromptModuleCatalog.activatedModuleIDs(
        requested: ["programming_precision", "programming_precision", "missing"],
        capabilities: [.workspace]
    )
    #expect(activated.filter { $0 == "programming_precision" }.count == 1)
    #expect(activated.contains("workspace_tool_rules"))
    #expect(activated.contains("workspace_execution_rules"))
    #expect(!activated.contains("missing"))
}

@Test func strategyCommitCombinesProvisionalEvidenceModulesAndMemoryDecision() throws {
    var state = AgentPhasedLoopState()
    let plan = AgentStrategyPlan(
        provisionalApproach: "Use the model's known architecture first.",
        recommendedApproach: "Keep that architecture and adopt the provider's stable cache key guidance.",
        alternatives: [.init(approach: "legacy", tradeoffs: "more tokens")],
        constraints: ["no side effects during research"],
        evidenceReferences: [.init(id: "official", uri: "https://example.com/docs", claim: "cache keys use stable identity")],
        taskMode: .coding,
        requestedModuleIDs: ["programming_precision"],
        memoryDecision: .query,
        memoryQueries: ["AgentLoop preferences"]
    )

    try state.commitStrategy(plan, memoryCapabilityAvailable: true)
    #expect(state.phase == .memoryPreparation)
    #expect(state.strategy?.provisionalApproach.contains("model") == true)
    #expect(state.strategy?.evidenceReferences.map(\.id) == ["official"])
    state.completeMemoryPreparation()
    #expect(state.phase == .taskExecution)
    state.prepareFinalOutput()
    #expect(state.phase == .finalSynthesis)
}

@Test func memorySkipRequiresAnEnumeratedExceptionAndConsistentCapability() {
    let invalid = AgentStrategyPlan(
        provisionalApproach: "p",
        recommendedApproach: "r",
        taskMode: .general,
        memoryDecision: .skip(.capabilityUnavailable)
    )
    #expect(throws: AgentStrategyPlanValidationError.memoryCapabilityUnavailable) {
        try AgentStrategyPlanValidator().validate(invalid, memoryCapabilityAvailable: true)
    }
}

@Test func externalResearchBatchesMixSourcesPreserveInputOrderAndBlockDuplicates() async {
    let coordinator = AgentExternalResearchCoordinator(sources: [
        AnyAgentExternalKnowledgeSource(PhasedTestKnowledgeSource(id: "web", kind: .web, delay: 40_000_000)),
        AnyAgentExternalKnowledgeSource(PhasedTestKnowledgeSource(id: "mcp", kind: .mcp, delay: 1_000_000)),
        AnyAgentExternalKnowledgeSource(PhasedTestKnowledgeSource(id: "kb", kind: .knowledgeBase, delay: 5_000_000))
    ])
    let requests = [
        AgentExternalResearchRequest(id: "1", sourceID: "web", query: "one"),
        AgentExternalResearchRequest(id: "2", sourceID: "mcp", query: "two"),
        AgentExternalResearchRequest(id: "3", sourceID: "kb", query: "three")
    ]
    let first = await coordinator.externalResearchSearchBatch(requests)
    #expect(first.map(\.id) == ["1", "2", "3"])
    #expect(first.allSatisfy { $0.selectedContent == nil })
    #expect(await coordinator.externalResearchSearchBatch(requests).isEmpty)

    let reads = await coordinator.externalResearchReadBatch(first.compactMap { item in
        item.uri.map { .init(id: item.id, sourceID: item.sourceID, uri: $0) }
    })
    #expect(reads.count == 3)
    #expect(reads.allSatisfy { $0.selectedContent?.hasPrefix("original") == true })
}

@Test func memoryQuerySearchesBothPartitionsMergesDeduplicatesAndSortsNewestFirst() async {
    let provider = PhasedTestMemoryProvider()
    let coordinator = AgentMemoryQueryCoordinator(provider: provider)
    let page = await coordinator.query("project", pageSize: 20)

    #expect(Set(await provider.observedPartitions()) == [.recent, .longTerm])
    #expect(page.items.map(\.id) == ["shared", "recent", "old"])
    #expect(page.items.allSatisfy { $0.provenance == nil })
    #expect(page.nextPage != nil)
}

@Test func evidenceAndRecoveryStatePreservePhaseModulesAndCompressedResearch() throws {
    var evidence = AgentEvidenceState()
    let firstQueryAddedEvidence = evidence.recordQuery("Swift cache", producedNewEvidence: true)
    let duplicateQueryAddedEvidence = evidence.recordQuery("swift CACHE", producedNewEvidence: true)
    #expect(firstQueryAddedEvidence)
    #expect(!duplicateQueryAddedEvidence)
    evidence.conclusions = ["stable prefix"]
    let recovery = AgentLoopRecoveryState(phase: .taskExecution, activeModuleIDs: ["programming_precision"], evidenceState: evidence)
    let roundTrip = try JSONDecoder().decode(AgentLoopRecoveryState.self, from: JSONEncoder().encode(recovery))
    #expect(roundTrip == recovery)
}

@Test func runtimeContextCapturesOneTrustedISOTimeAndTimezone() {
    let context = AgentRuntimeContext.capture(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    #expect(context.currentTimeISO8601.contains("1970-01-01T08:00:00"))
    #expect(context.timeZoneIdentifier == "Asia/Shanghai")
    #expect(context.trustedPrompt.contains("Current Time"))
}

@Test func phasedAgentLoopRunsStrategyBeforeMemoryAndPreparesProfileBeforeFinalAnswer() async throws {
    let commitJSON = #"{"provisionalApproach":"model approach","recommendedApproach":"evidence-adjusted approach","evidenceReferences":[{"id":"doc","claim":"supports approach"}],"taskMode":"coding","requestedModuleIDs":["programming_precision"],"memoryDecision":{"action":"query"},"memoryQueries":["project preference"],"memoryPageSize":20}"#
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(id: "strategy", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: commitJSON)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "memory", name: AgentPhaseToolContract.memoryQueryName, argumentsJSON: #"{"query":"project preference","pageSize":20}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"final answer"}"#)], finishReason: .toolCalls),
        .init(text: "final")
    ])
    var registry = AgentToolRegistry()
    registry.register(PhasedLoopMemoryTool(name: "memory_os_recent_context"))
    registry.register(PhasedLoopMemoryTool(name: "memory_os_knowledge_context"))
    registry.register(PhasedLoopMemoryTool(name: AgentContinuityPreflightPolicy.currentUserProfileToolName))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(executionMode: .phasedRetrieval, toolExposureMode: .all)
    )
    var finalText: String?
    for try await event in loop.run(.init(sessionID: "phased", userMessage: "Implement the change")) {
        if case .textComplete(let complete) = event { finalText = complete.text }
    }

    #expect(finalText == "final")
    let requests = await provider.capturedRequests()
    #expect(requests.map { $0.promptCacheContext?.phase } == [.strategyResearch, .memoryPreparation, .taskExecution, .finalSynthesis])
    #expect(requests[0].messages.first?.content.contains("Strategy Research is the first model task") == true)
    #expect(requests[1].tools.map(\.name).contains(AgentPhaseToolContract.memoryQueryName))
}
