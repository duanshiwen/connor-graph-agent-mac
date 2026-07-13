import Foundation

public struct CloudKnowledgeSearchTrace: Sendable, Equatable {
    public var contextID: String; public var knowledgeBaseID: String; public var publicationRunID: String
    public var channel: CloudKnowledgeSearchChannel; public var queryTerms: Set<String>; public var layers: Set<CloudKnowledgeLayer>
    public var baseSequence: Int; public var stagedSequence: Int; public var expiresAt: Date?
    public init(contextID: String, knowledgeBaseID: String, publicationRunID: String, channel: CloudKnowledgeSearchChannel, queryTerms: Set<String>, layers: Set<CloudKnowledgeLayer>, baseSequence: Int, stagedSequence: Int, expiresAt: Date? = nil) {
        self.contextID = contextID; self.knowledgeBaseID = knowledgeBaseID; self.publicationRunID = publicationRunID; self.channel = channel; self.queryTerms = queryTerms; self.layers = layers; self.baseSequence = baseSequence; self.stagedSequence = stagedSequence; self.expiresAt = expiresAt
    }
}

public actor CloudKnowledgePublishingTraceStore {
    private var traces: [String: CloudKnowledgeSearchTrace] = [:]
    public init() {}
    public func record(_ trace: CloudKnowledgeSearchTrace) { traces[trace.contextID] = trace }
    public func trace(id: String) -> CloudKnowledgeSearchTrace? { traces[id] }
    public func clear() { traces.removeAll() }
}

public struct CloudKnowledgePublishingTraceValidator: Sendable {
    public init() {}
    public func validate(operation: CloudKnowledgeOperation, trace: CloudKnowledgeSearchTrace?, context: CloudKnowledgePublishingContext, currentBaseSequence: Int, currentStagedSequence: Int, now: Date = Date()) throws {
        guard let trace else { throw CloudKnowledgeError.searchBeforeWriteRequired }
        guard trace.knowledgeBaseID == context.knowledgeBaseID, trace.publicationRunID == context.publicationRunID, trace.layers.contains(operation.layer) else { throw CloudKnowledgeError.searchContextNotRelevant }
        if let expiresAt = trace.expiresAt, expiresAt <= now { throw CloudKnowledgeError.searchContextStale }
        guard trace.baseSequence == currentBaseSequence, trace.stagedSequence == currentStagedSequence else { throw CloudKnowledgeError.searchContextStale }
        let operationTerms = Set(operation.semanticTerms.flatMap(Self.normalizedTerms))
        guard !operationTerms.isEmpty, !trace.queryTerms.isDisjoint(with: operationTerms) else { throw CloudKnowledgeError.searchContextNotRelevant }
        switch operation.layer {
        case .l2: guard trace.channel == .recentContext || trace.channel == .writeAssist else { throw CloudKnowledgeError.searchContextNotRelevant }
        case .l3, .l4: guard trace.channel == .knowledgeContext || trace.channel == .writeAssist else { throw CloudKnowledgeError.searchContextNotRelevant }
        }
    }
    public static func normalizedTerms(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh-Hans"))
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public actor CloudKnowledgeSearchClient {
    private let api: any CloudKnowledgeAPI; private let context: CloudKnowledgePublishingContext; private let traces: CloudKnowledgePublishingTraceStore
    public init(api: any CloudKnowledgeAPI, context: CloudKnowledgePublishingContext, traces: CloudKnowledgePublishingTraceStore) { self.api = api; self.context = context; self.traces = traces }
    public func search(channel: CloudKnowledgeSearchChannel, request: CloudKnowledgeSearchRequest) async throws -> CloudKnowledgeSearchResponse {
        var request = request; request.view = .combined; request.publicationRunID = context.publicationRunID
        let response = try await api.search(knowledgeBaseID: context.knowledgeBaseID, channel: channel, request: request)
        await traces.record(CloudKnowledgeSearchTrace(contextID: response.searchContextID, knowledgeBaseID: context.knowledgeBaseID, publicationRunID: context.publicationRunID, channel: channel, queryTerms: Set(CloudKnowledgePublishingTraceValidator.normalizedTerms(request.query)), layers: Set(request.layers), baseSequence: response.baseSequence, stagedSequence: response.stagedSequence, expiresAt: response.expiresAt))
        return response
    }
}

public struct CloudKnowledgeBatcher: Sendable {
    public var maximumOperations: Int; public var maximumEncodedBytes: Int
    public init(maximumOperations: Int = 50, maximumEncodedBytes: Int = 512_000) { self.maximumOperations = max(1, maximumOperations); self.maximumEncodedBytes = max(1_024, maximumEncodedBytes) }
    public func batches(_ operations: [CloudKnowledgeOperation]) throws -> [[CloudKnowledgeOperation]] {
        var result: [[CloudKnowledgeOperation]] = []; var current: [CloudKnowledgeOperation] = []
        let encoder = JSONEncoder()
        for operation in operations {
            let candidate = current + [operation]
            let candidateBytes = try encoder.encode(CloudKnowledgeOperationBatchRequest(operations: candidate)).count
            if !current.isEmpty && (candidate.count > maximumOperations || candidateBytes > maximumEncodedBytes) {
                result.append(current)
                current = [operation]
            } else {
                current = candidate
            }
            let currentBytes = try encoder.encode(CloudKnowledgeOperationBatchRequest(operations: current)).count
            if currentBytes > maximumEncodedBytes {
                throw CloudKnowledgeError.server(status: 413, code: "operation_too_large", message: "单项知识操作超过协议批次大小。")
            }
        }
        if !current.isEmpty { result.append(current) }; return result
    }
}

public struct CloudKnowledgeRetryPolicy: Sendable {
    public var maximumAttempts: Int; public var initialDelayNanoseconds: UInt64
    public init(maximumAttempts: Int = 3, initialDelayNanoseconds: UInt64 = 250_000_000) { self.maximumAttempts = max(1, maximumAttempts); self.initialDelayNanoseconds = initialDelayNanoseconds }
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true { do { return try await operation() } catch { attempt += 1; guard attempt < maximumAttempts, Self.isRetryable(error) else { throw error }; try await Task.sleep(nanoseconds: initialDelayNanoseconds << UInt64(attempt - 1)) } }
    }
    private static func isRetryable(_ error: Error) -> Bool { if case CloudKnowledgeError.server(let status, _, _) = error { return status == 429 || status >= 500 }; return error is URLError }
}

public struct CloudKnowledgeConflictResolver: Sendable {
    public init() {}
    public func rebase(api: any CloudKnowledgeAPI, runID: String, currentSequence: Int) async throws -> CloudKnowledgePublicationRun { try await api.rebase(runID: runID, request: CloudKnowledgeRebaseRequest(expectedBaseSequence: currentSequence)) }
}

public actor CloudKnowledgePublicationCoordinator {
    private let api: any CloudKnowledgeAPI; private let context: CloudKnowledgePublishingContext; private let traces: CloudKnowledgePublishingTraceStore
    private let validator: CloudKnowledgePublishingTraceValidator; private let batcher: CloudKnowledgeBatcher; private let retry: CloudKnowledgeRetryPolicy
    public private(set) var run: CloudKnowledgePublicationRun; public private(set) var processedLocalConversationIDs: [String] = []
    public init(api: any CloudKnowledgeAPI, context: CloudKnowledgePublishingContext, run: CloudKnowledgePublicationRun, traces: CloudKnowledgePublishingTraceStore = .init(), validator: CloudKnowledgePublishingTraceValidator = .init(), batcher: CloudKnowledgeBatcher = .init(), retry: CloudKnowledgeRetryPolicy = .init()) { self.api = api; self.context = context; self.run = run; self.traces = traces; self.validator = validator; self.batcher = batcher; self.retry = retry }
    public nonisolated func makeSearchClient() -> CloudKnowledgeSearchClient { CloudKnowledgeSearchClient(api: api, context: context, traces: traces) }
    public func stage(_ operations: [CloudKnowledgeOperation]) async throws {
        for operation in operations { try validator.validate(operation: operation, trace: await traces.trace(id: operation.searchContextID), context: context, currentBaseSequence: run.expectedBaseSequence, currentStagedSequence: run.currentStagedSequence) }
        for batch in try batcher.batches(operations) { let response = try await retry.run { try await api.appendOperations(runID: context.publicationRunID, request: CloudKnowledgeOperationBatchRequest(operations: batch)) }; run.currentStagedSequence = response.stagedSequence; run.status = .staging }
    }
    public func markLocalConversationProcessed(_ localID: String) { if !processedLocalConversationIDs.contains(localID) { processedLocalConversationIDs.append(localID) } }
    public func refresh() async throws { run = try await api.publicationRun(id: context.publicationRunID) }
    public func validate() async throws -> CloudKnowledgeValidationResult { run.status = .validating; let result = try await api.validate(runID: context.publicationRunID); run.status = result.valid ? .ready : .staging; return result }
    public func rebase(to sequence: Int) async throws { run = try await api.rebase(runID: context.publicationRunID, request: .init(expectedBaseSequence: sequence)); await traces.clear() }
    public func commit() async throws -> CloudKnowledgeCommitResult { let result = try await api.commit(runID: context.publicationRunID); run.status = .committed; return result }
    public func abandon() async throws { try await api.abandon(runID: context.publicationRunID); run.status = .abandoned; await traces.clear() }
}

public struct CloudKnowledgeLocalConversation: Sendable, Equatable { public var localID: String; public var title: String; public var localPrompt: String; public init(localID: String, title: String, localPrompt: String) { self.localID = localID; self.title = title; self.localPrompt = localPrompt } }
public struct CloudKnowledgeStagedConversationProcessor: Sendable {
    public init() {}
    public func process(_ conversations: [CloudKnowledgeLocalConversation], coordinator: CloudKnowledgePublicationCoordinator, localLLM: @Sendable (CloudKnowledgeLocalConversation, CloudKnowledgeSearchClient) async throws -> [CloudKnowledgeOperation]) async throws {
        for conversation in conversations { try Task.checkCancellation(); let searchClient = coordinator.makeSearchClient(); let operations = try await localLLM(conversation, searchClient); try await coordinator.stage(operations); await coordinator.markLocalConversationProcessed(conversation.localID) }
    }
}
