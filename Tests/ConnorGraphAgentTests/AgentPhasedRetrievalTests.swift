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

private actor PhasedProfilePageRecorder {
    private var pages: [Int] = []
    func record(_ page: Int) { pages.append(page) }
    func snapshot() -> [Int] { pages }
}

private struct PagedPhasedProfileTool: AgentTool {
    let name = AgentContinuityPreflightPolicy.currentUserProfileToolName
    let recorder: PhasedProfilePageRecorder
    let permission: AgentPermissionCapability = .readGraph
    let description = "paged profile"
    let inputSchema = AgentToolInputSchema.object(properties: [
        "page": .integer(description: ""), "pageSize": .integer(description: ""),
        "purpose": .string(description: ""), "view": .string(description: "")
    ], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let page = arguments.int("page") ?? 1
        await recorder.record(page)
        let nextPage = page == 1 ? "2" : "null"
        let json = "{\"success\":true,\"records\":[{\"recordID\":\"profile-\(page)\"}],\"nextPage\":\(nextPage)}"
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: json,
            contentJSON: json
        )
    }
}

private actor PhasedMemoryCallRecorder {
    private var calls: [(String, Int)] = []
    func record(name: String, page: Int) { calls.append((name, page)) }
    func snapshot() -> [(String, Int)] { calls }
}

private struct PagedPhasedMemoryTool: AgentTool {
    let name: String
    let recorder: PhasedMemoryCallRecorder
    let permission: AgentPermissionCapability = .readGraph
    let description = "paged test memory"
    let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: ""), "page": .integer(description: ""), "pageSize": .integer(description: ""), "depth": .integer(description: "")
    ], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let page = arguments.int("page") ?? 1
        await recorder.record(name: name, page: page)
        let json: String
        if name == "memory_os_recent_context", page == 1 {
            json = #"{"success":true,"records":[{"recordID":"r1","occurredAt":"2026-07-30T10:00:00Z"}],"nextPage":2}"#
        } else if name == "memory_os_recent_context" {
            json = #"{"success":true,"records":[{"recordID":"r2","occurredAt":"2026-07-29T10:00:00Z"}],"nextPage":null}"#
        } else {
            json = #"{"success":true,"records":[{"recordID":"l1","occurredAt":"2026-07-28T10:00:00Z"}],"nextPage":null}"#
        }
        return AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: json, contentJSON: json)
    }
}

private actor CursorFollowingPhasedProvider: AgentModelProvider {
    let modelID = "cursor-phased"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: true, supportsStructuredOutput: true, supportsVision: false)
    private var callIndex = 0
    private(set) var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        defer { callIndex += 1 }
        switch callIndex {
        case 0:
            let commit = #"{"provisionalApproach":"p","recommendedApproach":"r","taskMode":"general","memoryDecision":{"action":"query"},"memoryQueries":["project"],"memoryPageSize":20}"#
            return .init(text: nil, toolCalls: [.init(id: "commit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: commit)], finishReason: .toolCalls)
        case 1:
            return .init(text: nil, toolCalls: [.init(id: "memory-1", name: AgentPhaseToolContract.memoryQueryName, argumentsJSON: #"{"query":"project"}"#)], finishReason: .toolCalls)
        case 2:
            let toolMessage = try #require(request.messages.last { $0.name == AgentPhaseToolContract.memoryQueryName })
            let data = try #require(toolMessage.content.data(using: .utf8))
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let cursor = try #require(object["nextPage"] as? String)
            let cursorJSON = String(decoding: try JSONEncoder().encode(cursor), as: UTF8.self)
            return .init(text: nil, toolCalls: [.init(id: "memory-2", name: AgentPhaseToolContract.memoryQueryName, argumentsJSON: "{\"query\":\"project\",\"page\":\(cursorJSON)}")], finishReason: .toolCalls)
        case 3:
            return .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls)
        default:
            return .init(text: "done")
        }
    }
}

private struct PhasedOversizedTool: AgentTool {
    let name = "oversized_result"
    let permission: AgentPermissionCapability = .readGraph
    let description = "oversized test result"
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])
    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: String(repeating: "evidence ", count: 20_000))
    }
}

private actor OverflowRecoveryPhasedProvider: AgentModelProvider {
    let modelID = "phased-overflow"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: true, supportsStructuredOutput: true, supportsVision: false)
    private var callIndex = 0
    private(set) var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        defer { callIndex += 1 }
        switch callIndex {
        case 0:
            return .init(text: nil, toolCalls: [.init(id: "commit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"known","recommendedApproach":"recovered approach","taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#)], finishReason: .toolCalls)
        case 1:
            return .init(text: nil, toolCalls: [.init(id: "large", name: "oversized_result", argumentsJSON: #"{}"#)], finishReason: .toolCalls)
        case 2:
            throw OpenAICompatibleProviderError.httpStatus(400, message: "context length exceeded")
        case 3:
            return .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls)
        default:
            return .init(text: "recovered")
        }
    }
}

private actor PhasedConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0
    func begin() { active += 1; maximumActive = max(maximumActive, active) }
    func end() { active -= 1 }
}

private struct PhasedConcurrentReadTool: AgentTool {
    let name: String
    let probe: PhasedConcurrencyProbe
    let permission: AgentPermissionCapability = .readGraph
    let description = "parallel read"
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])
    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        await probe.begin()
        try await Task.sleep(nanoseconds: 30_000_000)
        await probe.end()
        return AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: name)
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
    #expect(throws: AgentStrategyPlanValidationError.invalidCommitPhase(.finalSynthesis)) {
        try state.commitStrategy(plan, memoryCapabilityAvailable: true)
    }
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
    let mismatchedMode = AgentStrategyPlan(
        provisionalApproach: "p",
        recommendedApproach: "r",
        taskMode: .research,
        memoryDecision: .skip(.historyIndependentMechanicalOrCodingTask)
    )
    #expect(throws: AgentStrategyPlanValidationError.invalidMemorySkipReasonForTaskMode) {
        try AgentStrategyPlanValidator().validate(mismatchedMode, memoryCapabilityAvailable: true)
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
    registry.register(PhasedLoopMemoryTool(name: "Read"))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(toolExposureMode: .all)
    )
    var finalText: String?
    for try await event in loop.run(.init(sessionID: "phased", userMessage: "Implement the change")) {
        if case .textComplete(let complete) = event { finalText = complete.text }
    }

    #expect(finalText == "final")
    let requests = await provider.capturedRequests()
    #expect(requests.map { $0.promptCacheContext?.phase } == [.strategyResearch, .memoryPreparation, .taskExecution, .finalSynthesis])
    #expect(requests[0].messages.first?.content.contains("Strategy Research is the first model task") == true)
    #expect(requests[0].messages.first?.content.contains("## Programming and Precision Work") == false)
    #expect(requests[1].messages.first?.content.contains("## Programming and Precision Work") == true)
    #expect(requests[0].messages[0].content.contains("Current Time:") == false)
    #expect(requests[0].messages[1].content.contains("Current Time:") == true)
    #expect(requests[1].tools.map(\.name).contains(AgentPhaseToolContract.memoryQueryName))
    #expect(requests[2].tools.map(\.name).contains(AgentPhaseToolContract.memoryQueryName) == false)
}

@Test func phasedLoopRejectsMemorySkipWhenUserExplicitlyRequiresMemory() async throws {
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(id: "invalid-skip", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p","recommendedApproach":"r","taskMode":"general","memoryDecision":{"action":"skip","reason":"userExplicitlyDisabled"}}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "valid-strategy", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p","recommendedApproach":"r","taskMode":"general","memoryDecision":{"action":"query"},"memoryQueries":["沟通偏好"],"memoryPageSize":20}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "memory", name: AgentPhaseToolContract.memoryQueryName, argumentsJSON: #"{"query":"沟通偏好"}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls),
        .init(text: "done")
    ])
    var registry = AgentToolRegistry()
    registry.register(PhasedLoopMemoryTool(name: "memory_os_recent_context"))
    registry.register(PhasedLoopMemoryTool(name: "memory_os_knowledge_context"))
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    for try await _ in loop.run(.init(sessionID: "memory-required", userMessage: "必须先查询相关 Memory 再回答")) {}

    let requests = await provider.capturedRequests()
    #expect(requests.map { $0.promptCacheContext?.phase } == [
        .strategyResearch, .strategyResearch, .memoryPreparation, .taskExecution, .finalSynthesis
    ])
    #expect(requests[3].tools.map(\.name).contains(AgentPhaseToolContract.memoryQueryName) == false)
    #expect(requests[1].messages.contains {
        $0.role == .system && $0.content.contains("user explicitly requires Memory")
    })
}

@Test func phasedLoopUsesRegisteredExternalSourceAndCompressesOlderResearch() async throws {
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(id: "search", name: AgentPhaseToolContract.externalSearchBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","query":"cache"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "read", name: AgentPhaseToolContract.externalReadBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","uri":"https://example.com/cache"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "commit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p","recommendedApproach":"r","evidenceReferences":[{"id":"read-0","uri":"https://example.com/cache","claim":"original source"}],"taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls),
        .init(text: "done")
    ])
    let source = AnyAgentExternalKnowledgeSource(PhasedTestKnowledgeSource(id: "enterprise", kind: .enterpriseKnowledge, delay: 0))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: .init(toolExposureMode: .all),
        externalKnowledgeSources: [source]
    )
    for try await _ in loop.run(.init(sessionID: "external-source", userMessage: "Implement cache support")) {}

    let requests = await provider.capturedRequests()
    #expect(requests[0].messages[1].content.contains("enterprise [enterpriseKnowledge]"))
    #expect(requests[0].tools.map(\.name).contains(AgentPhaseToolContract.externalSearchBatchName))
    #expect(requests[0].tools.map(\.name).contains(AgentPhaseToolContract.externalReadBatchName))
    let commitRequest = requests[2]
    #expect(commitRequest.messages.contains { $0.role == .tool && $0.toolCallID == "search" && $0.content.contains("Compressed research evidence") })
    #expect(commitRequest.messages.contains {
        $0.role == .tool && $0.toolCallID == "read"
            && $0.content.contains("selectedContent") && $0.content.contains("original")
    })
}

@Test func phasedMemoryOpaqueCursorContinuesOnlyUnfinishedPartition() async throws {
    let recorder = PhasedMemoryCallRecorder()
    var registry = AgentToolRegistry()
    registry.register(PagedPhasedMemoryTool(name: "memory_os_recent_context", recorder: recorder))
    registry.register(PagedPhasedMemoryTool(name: "memory_os_knowledge_context", recorder: recorder))
    let provider = CursorFollowingPhasedProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(toolExposureMode: .all)
    )
    for try await _ in loop.run(.init(sessionID: "cursor", userMessage: "Give a personalized answer")) {}

    let calls = await recorder.snapshot()
    #expect(calls.filter { $0.0 == "memory_os_recent_context" }.map(\.1) == [1, 2])
    #expect(calls.filter { $0.0 == "memory_os_knowledge_context" }.map(\.1) == [1])
    let requests = await provider.requests
    let firstMemory = try #require(requests[2].messages.last { $0.toolCallID == "memory-1" })
    #expect(!firstMemory.content.contains("recent"))
    #expect(!firstMemory.content.contains("longTerm"))
}

@Test func phasedContextRecoveryRetainsPhaseModulesEvidenceAndDynamicRuntime() async throws {
    var registry = AgentToolRegistry()
    registry.register(PhasedOversizedTool())
    let provider = OverflowRecoveryPhasedProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(toolExposureMode: .all)
    )
    for try await _ in loop.run(.init(sessionID: "recovery", userMessage: "Implement it")) {}

    let requests = await provider.requests
    let recovered = requests[3]
    #expect(recovered.messages.contains { $0.role == .system && $0.content.contains("## Agent Loop Recovery State") })
    #expect(recovered.messages.contains { $0.role == .system && $0.content.contains("phase: taskExecution") })
    #expect(recovered.messages.contains { $0.role == .system && $0.content.contains("recovered approach") })
    #expect(recovered.messages.contains { $0.role == .system && $0.content.contains("Current Time:") })
}

@Test func phasedTaskExecutionRunsIndependentReadOnlyToolsInParallelByDefault() async throws {
    let probe = PhasedConcurrencyProbe()
    var registry = AgentToolRegistry()
    registry.register(PhasedConcurrentReadTool(name: "read_a", probe: probe))
    registry.register(PhasedConcurrentReadTool(name: "read_b", probe: probe))
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(id: "commit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p","recommendedApproach":"r","taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [
            .init(id: "a", name: "read_a", argumentsJSON: #"{}"#),
            .init(id: "b", name: "read_b", argumentsJSON: #"{}"#)
        ], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls),
        .init(text: "done")
    ])
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(toolExposureMode: .all)
    )
    for try await _ in loop.run(.init(sessionID: "parallel", userMessage: "Read both")) {}
    let maximumActive = await probe.maximumActive
    #expect(maximumActive == 2)
}

@Test func prepareFinalOutputPaginatesProfileInternallyBeforeOneFinalModelCall() async throws {
    let recorder = PhasedProfilePageRecorder()
    var registry = AgentToolRegistry()
    registry.register(PagedPhasedProfileTool(recorder: recorder))
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(
            id: "commit",
            name: AgentPhaseToolContract.commitStrategyName,
            argumentsJSON: #"{"provisionalApproach":"p","recommendedApproach":"r","taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#
        )], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"answer"}"#)], finishReason: .toolCalls),
        .init(text: "done")
    ])
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: .init(toolExposureMode: .all)
    )

    for try await _ in loop.run(.init(sessionID: "profile-pages", userMessage: "Give me a personalized answer")) {}

    #expect(await recorder.snapshot() == [1, 2])
    let requests = await provider.capturedRequests()
    #expect(requests.count == 3)
    #expect(requests.map { $0.promptCacheContext?.phase } == [.strategyResearch, .taskExecution, .finalSynthesis])
}

@Test func finalSynthesisResearchReentersStrategyAndRequiresRecommit() async throws {
    let provider = PhasedLoopModelProvider(responses: [
        .init(text: nil, toolCalls: [.init(id: "initial-search", name: AgentPhaseToolContract.externalSearchBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","query":"initial"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "initial-read", name: AgentPhaseToolContract.externalReadBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","uri":"https://example.com/initial"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "initial-commit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p1","recommendedApproach":"r1","evidenceReferences":[{"id":"initial-read-0","uri":"https://example.com/initial","claim":"initial evidence"}],"taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare-1", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"check preferences"}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "refresh-search", name: AgentPhaseToolContract.externalSearchBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","query":"preference-adjusted"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "refresh-read", name: AgentPhaseToolContract.externalReadBatchName, argumentsJSON: #"{"requests":[{"sourceID":"enterprise","uri":"https://example.com/preference-adjusted"}]}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "recommit", name: AgentPhaseToolContract.commitStrategyName, argumentsJSON: #"{"provisionalApproach":"p2","recommendedApproach":"r2","evidenceReferences":[{"id":"refresh-read-0","uri":"https://example.com/preference-adjusted","claim":"updated evidence"}],"taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#)], finishReason: .toolCalls),
        .init(text: nil, toolCalls: [.init(id: "prepare-2", name: AgentPhaseToolContract.prepareFinalOutputName, argumentsJSON: #"{"reason":"final answer"}"#)], finishReason: .toolCalls),
        .init(text: "updated final")
    ])
    let source = AnyAgentExternalKnowledgeSource(PhasedTestKnowledgeSource(id: "enterprise", kind: .enterpriseKnowledge, delay: 0))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: .init(toolExposureMode: .all),
        externalKnowledgeSources: [source]
    )

    for try await _ in loop.run(.init(sessionID: "final-research", userMessage: "Research and recommend")) {}

    let requests = await provider.capturedRequests()
    #expect(requests.map { $0.promptCacheContext?.phase } == [
        .strategyResearch, .strategyResearch, .strategyResearch, .taskExecution,
        .finalSynthesis, .strategyResearch, .strategyResearch, .taskExecution, .finalSynthesis
    ])
    #expect(requests[5].messages.contains { $0.role == .system && $0.content.contains("call agent_commit_strategy again") })
}
