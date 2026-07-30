import Foundation

public enum AgentLoopPhase: String, Codable, CaseIterable, Sendable, Equatable {
    case strategyResearch
    case memoryPreparation
    case taskExecution
    case finalSynthesis
}

public struct AgentRuntimeContext: Codable, Sendable, Equatable {
    public var currentTimeISO8601: String
    public var timeZoneIdentifier: String

    public init(currentTimeISO8601: String, timeZoneIdentifier: String) {
        self.currentTimeISO8601 = currentTimeISO8601
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static func capture(now: Date = Date(), timeZone: TimeZone = .current) -> Self {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return Self(currentTimeISO8601: formatter.string(from: now), timeZoneIdentifier: timeZone.identifier)
    }

    public var trustedPrompt: String {
        "Runtime Context (trusted, captured once for this user run): Current Time: \(currentTimeISO8601); Timezone: \(timeZoneIdentifier)."
    }
}

public enum AgentStrategyTaskMode: String, Codable, Sendable, Equatable {
    case mechanical
    case coding
    case research
    case creative
    case recommendation
    case general
}

public enum AgentMemorySkipReason: String, Codable, Sendable, Equatable {
    case userExplicitlyDisabled
    case mechanicalTextTransformation
    case deterministicComputationWithCompleteInput
    case historyIndependentMechanicalOrCodingTask
    case memoryCapabilityUnavailable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "capabilityUnavailable" {
            self = .memoryCapabilityUnavailable
            return
        }
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown Memory skip reason: \(rawValue)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AgentStrategyMemoryDecision: Sendable, Equatable, Codable {
    case query
    case skip(AgentMemorySkipReason)

    private enum CodingKeys: String, CodingKey { case action, reason }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .action) {
        case "query": self = .query
        case "skip": self = .skip(try container.decode(AgentMemorySkipReason.self, forKey: .reason))
        default: throw DecodingError.dataCorruptedError(forKey: .action, in: container, debugDescription: "Expected query or skip")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .query:
            try container.encode("query", forKey: .action)
        case .skip(let reason):
            try container.encode("skip", forKey: .action)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public struct AgentStrategyAlternative: Codable, Sendable, Equatable {
    public var approach: String
    public var tradeoffs: String

    public init(approach: String, tradeoffs: String) {
        self.approach = approach
        self.tradeoffs = tradeoffs
    }
}

public struct AgentStrategyEvidenceReference: Codable, Sendable, Equatable {
    public var id: String
    public var uri: String?
    public var claim: String

    public init(id: String, uri: String? = nil, claim: String) {
        self.id = id
        self.uri = uri
        self.claim = claim
    }
}

public struct AgentStrategyPlan: Codable, Sendable, Equatable {
    public var provisionalApproach: String
    public var recommendedApproach: String
    public var alternatives: [AgentStrategyAlternative]
    public var constraints: [String]
    public var evidenceReferences: [AgentStrategyEvidenceReference]
    public var unresolvedQuestions: [String]
    public var taskMode: AgentStrategyTaskMode
    public var requestedModuleIDs: [AgentPromptModuleID]
    public var memoryDecision: AgentStrategyMemoryDecision
    public var memoryQueries: [String]
    public var memoryPageSize: Int

    public init(
        provisionalApproach: String,
        recommendedApproach: String,
        alternatives: [AgentStrategyAlternative] = [],
        constraints: [String] = [],
        evidenceReferences: [AgentStrategyEvidenceReference] = [],
        unresolvedQuestions: [String] = [],
        taskMode: AgentStrategyTaskMode,
        requestedModuleIDs: [AgentPromptModuleID] = [],
        memoryDecision: AgentStrategyMemoryDecision,
        memoryQueries: [String] = [],
        memoryPageSize: Int = 20
    ) {
        self.provisionalApproach = provisionalApproach
        self.recommendedApproach = recommendedApproach
        self.alternatives = alternatives
        self.constraints = constraints
        self.evidenceReferences = evidenceReferences
        self.unresolvedQuestions = unresolvedQuestions
        self.taskMode = taskMode
        self.requestedModuleIDs = requestedModuleIDs
        self.memoryDecision = memoryDecision
        self.memoryQueries = memoryQueries
        self.memoryPageSize = memoryPageSize
    }

    private enum CodingKeys: String, CodingKey {
        case provisionalApproach, recommendedApproach, alternatives, constraints, evidenceReferences
        case unresolvedQuestions, taskMode, requestedModuleIDs, memoryDecision, memoryQueries, memoryPageSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provisionalApproach = try container.decode(String.self, forKey: .provisionalApproach)
        recommendedApproach = try container.decode(String.self, forKey: .recommendedApproach)
        alternatives = try container.decodeIfPresent([AgentStrategyAlternative].self, forKey: .alternatives) ?? []
        constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        evidenceReferences = try container.decodeIfPresent([AgentStrategyEvidenceReference].self, forKey: .evidenceReferences) ?? []
        unresolvedQuestions = try container.decodeIfPresent([String].self, forKey: .unresolvedQuestions) ?? []
        taskMode = try container.decode(AgentStrategyTaskMode.self, forKey: .taskMode)
        requestedModuleIDs = try container.decodeIfPresent([AgentPromptModuleID].self, forKey: .requestedModuleIDs) ?? []
        memoryDecision = try container.decode(AgentStrategyMemoryDecision.self, forKey: .memoryDecision)
        memoryQueries = try container.decodeIfPresent([String].self, forKey: .memoryQueries) ?? []
        memoryPageSize = try container.decodeIfPresent(Int.self, forKey: .memoryPageSize) ?? 20
    }
}

public enum AgentStrategyPlanValidationError: Error, Sendable, Equatable {
    case invalidCommitPhase(AgentLoopPhase)
    case missingProvisionalApproach
    case missingRecommendedApproach
    case invalidMemoryPageSize
    case memoryQueriesRequired
    case memoryQueriesForbiddenWhenSkipped
    case memoryCapabilityUnavailable
    case invalidMemorySkipReasonForTaskMode
}

public struct AgentStrategyPlanValidator: Sendable {
    public init() {}

    public func validate(_ plan: AgentStrategyPlan, memoryCapabilityAvailable: Bool) throws {
        guard !plan.provisionalApproach.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentStrategyPlanValidationError.missingProvisionalApproach
        }
        guard !plan.recommendedApproach.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentStrategyPlanValidationError.missingRecommendedApproach
        }
        guard (1...100).contains(plan.memoryPageSize) else {
            throw AgentStrategyPlanValidationError.invalidMemoryPageSize
        }
        switch plan.memoryDecision {
        case .query:
            guard memoryCapabilityAvailable else { throw AgentStrategyPlanValidationError.memoryCapabilityUnavailable }
            guard !normalizedQueries(plan.memoryQueries).isEmpty else { throw AgentStrategyPlanValidationError.memoryQueriesRequired }
        case .skip(let reason):
            guard plan.memoryQueries.isEmpty else { throw AgentStrategyPlanValidationError.memoryQueriesForbiddenWhenSkipped }
            if reason == .memoryCapabilityUnavailable, memoryCapabilityAvailable {
                throw AgentStrategyPlanValidationError.memoryCapabilityUnavailable
            }
            if reason == .mechanicalTextTransformation || reason == .deterministicComputationWithCompleteInput,
               plan.taskMode != .mechanical {
                throw AgentStrategyPlanValidationError.invalidMemorySkipReasonForTaskMode
            }
            if reason == .historyIndependentMechanicalOrCodingTask,
               plan.taskMode != .mechanical,
               plan.taskMode != .coding {
                throw AgentStrategyPlanValidationError.invalidMemorySkipReasonForTaskMode
            }
        }
    }

    private func normalizedQueries(_ queries: [String]) -> [String] {
        queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public enum AgentExternalKnowledgeSourceKind: String, Codable, Sendable, Equatable {
    case web
    case mcp
    case knowledgeBase
    case officialDocumentation
    case enterpriseKnowledge
    case otherReadOnly
}

public struct AgentExternalResearchRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var query: String
    public var cursor: String?

    public init(id: String = UUID().uuidString, sourceID: String, query: String, cursor: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.query = query
        self.cursor = cursor
    }
}

public struct AgentExternalResearchReadRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var uri: String
    public var selection: String?

    public init(id: String = UUID().uuidString, sourceID: String, uri: String, selection: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.uri = uri
        self.selection = selection
    }
}

public struct AgentExternalKnowledgeItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var uri: String?
    public var title: String
    public var summary: String
    public var selectedContent: String?
    public var occurredAt: Date?
    public var nextPage: String?
    public var error: String?

    public init(id: String, sourceID: String, uri: String? = nil, title: String, summary: String, selectedContent: String? = nil, occurredAt: Date? = nil, nextPage: String? = nil, error: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.uri = uri
        self.title = title
        self.summary = summary
        self.selectedContent = selectedContent
        self.occurredAt = occurredAt
        self.nextPage = nextPage
        self.error = error
    }
}

public protocol AgentExternalKnowledgeSource: Sendable {
    var id: String { get }
    var kind: AgentExternalKnowledgeSourceKind { get }
    var isReadOnly: Bool { get }
    func search(_ request: AgentExternalResearchRequest) async throws -> [AgentExternalKnowledgeItem]
    func read(_ request: AgentExternalResearchReadRequest) async throws -> AgentExternalKnowledgeItem
}

public struct AgentExternalKnowledgeSourceDescriptor: Codable, Sendable, Equatable {
    public var id: String
    public var kind: AgentExternalKnowledgeSourceKind
    public var summary: String

    public init(id: String, kind: AgentExternalKnowledgeSourceKind, summary: String) {
        self.id = id
        self.kind = kind
        self.summary = summary
    }
}

public struct AnyAgentExternalKnowledgeSource: AgentExternalKnowledgeSource, Sendable {
    public let id: String
    public let kind: AgentExternalKnowledgeSourceKind
    public let isReadOnly: Bool
    private let searchClosure: @Sendable (AgentExternalResearchRequest) async throws -> [AgentExternalKnowledgeItem]
    private let readClosure: @Sendable (AgentExternalResearchReadRequest) async throws -> AgentExternalKnowledgeItem

    public init<S: AgentExternalKnowledgeSource>(_ source: S) {
        id = source.id
        kind = source.kind
        isReadOnly = source.isReadOnly
        searchClosure = source.search
        readClosure = source.read
    }

    public init(
        id: String,
        kind: AgentExternalKnowledgeSourceKind,
        isReadOnly: Bool = true,
        search: @escaping @Sendable (AgentExternalResearchRequest) async throws -> [AgentExternalKnowledgeItem],
        read: @escaping @Sendable (AgentExternalResearchReadRequest) async throws -> AgentExternalKnowledgeItem
    ) {
        self.id = id
        self.kind = kind
        self.isReadOnly = isReadOnly
        self.searchClosure = search
        self.readClosure = read
    }

    public func search(_ request: AgentExternalResearchRequest) async throws -> [AgentExternalKnowledgeItem] { try await searchClosure(request) }
    public func read(_ request: AgentExternalResearchReadRequest) async throws -> AgentExternalKnowledgeItem { try await readClosure(request) }
}

public struct AgentToolBatchScheduler: Sendable {
    public var maximumConcurrency: Int

    public init(maximumConcurrency: Int = 4) {
        self.maximumConcurrency = max(1, maximumConcurrency)
    }

    public func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard !inputs.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, Output).self, returning: [Output].self) { group in
            var nextIndex = 0
            var ordered = Array<Output?>(repeating: nil, count: inputs.count)
            func submit(_ index: Int) {
                group.addTask { (index, await operation(inputs[index])) }
            }
            while nextIndex < min(maximumConcurrency, inputs.count) {
                submit(nextIndex)
                nextIndex += 1
            }
            while let (index, output) = await group.next() {
                ordered[index] = output
                if nextIndex < inputs.count {
                    submit(nextIndex)
                    nextIndex += 1
                }
            }
            return ordered.compactMap { $0 }
        }
    }
}

public struct AgentToolBatchResultReducer: Sendable {
    public var perItemTokenLimit: Int
    public var batchTokenLimit: Int
    public var estimator: AgentTextTokenEstimator

    public init(perItemTokenLimit: Int = 2_000, batchTokenLimit: Int = 8_000, estimator: AgentTextTokenEstimator = AgentTextTokenEstimator()) {
        self.perItemTokenLimit = max(1, perItemTokenLimit)
        self.batchTokenLimit = max(1, batchTokenLimit)
        self.estimator = estimator
    }

    public func reduce(_ items: [AgentExternalKnowledgeItem], includeSelectedContent: Bool) -> [AgentExternalKnowledgeItem] {
        var seen = Set<String>()
        var remaining = batchTokenLimit
        var output: [AgentExternalKnowledgeItem] = []
        for var item in items {
            let identity = item.uri?.lowercased() ?? "\(item.sourceID):\(item.id)"
            guard seen.insert(identity).inserted, remaining > 0 else { continue }
            let itemLimit = min(perItemTokenLimit, remaining)
            item.summary = truncate(item.summary, toTokens: min(itemLimit, max(1, itemLimit / 3)))
            item.selectedContent = includeSelectedContent ? item.selectedContent.map { truncate($0, toTokens: itemLimit) } : nil
            let used = estimator.estimateTokenCount(item.summary + (item.selectedContent ?? ""))
            remaining = max(0, remaining - used)
            output.append(item)
        }
        return output
    }

    private func truncate(_ text: String, toTokens limit: Int) -> String {
        guard estimator.estimateTokenCount(text) > limit else { return text }
        return String(text.prefix(max(1, limit * 4))) + "\n[truncated]"
    }
}

public actor AgentExternalResearchCoordinator {
    private let sources: [String: AnyAgentExternalKnowledgeSource]
    private let scheduler: AgentToolBatchScheduler
    private let reducer: AgentToolBatchResultReducer
    private var completedSignatures = Set<String>()

    public init(sources: [AnyAgentExternalKnowledgeSource], scheduler: AgentToolBatchScheduler = .init(), reducer: AgentToolBatchResultReducer = .init()) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.scheduler = scheduler
        self.reducer = reducer
    }

    public func externalResearchSearchBatch(_ requests: [AgentExternalResearchRequest]) async -> [AgentExternalKnowledgeItem] {
        let accepted = requests.filter { completedSignatures.insert("search:\($0.sourceID):\($0.query.lowercased()):\($0.cursor ?? "")").inserted }
        let sources = self.sources
        let nested = await scheduler.run(accepted) { request -> [AgentExternalKnowledgeItem] in
            guard let source = sources[request.sourceID], source.isReadOnly else {
                return [.init(id: request.id, sourceID: request.sourceID, title: "Unavailable source", summary: "", error: "Unknown or non-read-only knowledge source")]
            }
            do { return try await source.search(request) }
            catch { return [.init(id: request.id, sourceID: request.sourceID, title: "Search failed", summary: "", error: String(describing: error))] }
        }
        return reducer.reduce(nested.flatMap { $0 }, includeSelectedContent: false)
    }

    public func externalResearchReadBatch(_ requests: [AgentExternalResearchReadRequest]) async -> [AgentExternalKnowledgeItem] {
        let accepted = requests.filter { completedSignatures.insert("read:\($0.sourceID):\($0.uri):\($0.selection ?? "")").inserted }
        let sources = self.sources
        let items = await scheduler.run(accepted) { request -> AgentExternalKnowledgeItem in
            guard let source = sources[request.sourceID], source.isReadOnly else {
                return .init(id: request.id, sourceID: request.sourceID, uri: request.uri, title: "Unavailable source", summary: "", error: "Unknown or non-read-only knowledge source")
            }
            do { return try await source.read(request) }
            catch { return .init(id: request.id, sourceID: request.sourceID, uri: request.uri, title: "Read failed", summary: "", error: String(describing: error)) }
        }
        return reducer.reduce(items, includeSelectedContent: true)
    }
}

public enum AgentMemoryPartition: String, Codable, CaseIterable, Sendable, Equatable { case recent, longTerm }

public struct AgentMemoryQueryRequest: Codable, Sendable, Equatable {
    public var query: String
    public var pageSize: Int
    public var cursor: String?

    public init(query: String, pageSize: Int = 20, cursor: String? = nil) {
        self.query = query
        self.pageSize = pageSize
        self.cursor = cursor
    }
}

public struct AgentMemoryQueryItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var eventTime: Date
    public var citation: String?
    public var provenance: String?

    public init(id: String, text: String, eventTime: Date, citation: String? = nil, provenance: String? = nil) {
        self.id = id
        self.text = text
        self.eventTime = eventTime
        self.citation = citation
        self.provenance = provenance
    }
}

public struct AgentMemoryPartitionPage: Sendable, Equatable {
    public var items: [AgentMemoryQueryItem]
    public var nextCursor: String?
    public init(items: [AgentMemoryQueryItem], nextCursor: String? = nil) { self.items = items; self.nextCursor = nextCursor }
}

public protocol AgentMemoryQueryProvider: Sendable {
    func query(_ request: AgentMemoryQueryRequest, partition: AgentMemoryPartition) async throws -> AgentMemoryPartitionPage
}

public struct AgentMemoryQueryPage: Codable, Sendable, Equatable {
    public var items: [AgentMemoryQueryItem]
    public var nextPage: String?
    public var errors: [String]

    public init(items: [AgentMemoryQueryItem], nextPage: String? = nil, errors: [String] = []) {
        self.items = items
        self.nextPage = nextPage
        self.errors = errors
    }
}

public actor AgentMemoryQueryCoordinator {
    private let provider: any AgentMemoryQueryProvider
    private struct CursorState: Sendable {
        var query: String
        var pageSize: Int
        var partitionCursors: [AgentMemoryPartition: String]
        var bufferedItems: [AgentMemoryQueryItem]
        var seenItemIDs: Set<String>
    }
    private var cursors: [String: CursorState] = [:]

    public init(provider: any AgentMemoryQueryProvider) { self.provider = provider }

    public func query(_ query: String, pageSize: Int = 20, page: String? = nil) async -> AgentMemoryQueryPage {
        let size = min(100, max(1, pageSize))
        let previousState: CursorState?
        if let page {
            guard let saved = cursors[page] else {
                return AgentMemoryQueryPage(items: [], errors: ["Unknown or expired Memory nextPage token"])
            }
            guard saved.query == query, saved.pageSize == size else {
                return AgentMemoryQueryPage(items: [], errors: ["Memory pagination must keep the original query and pageSize"])
            }
            cursors.removeValue(forKey: page)
            previousState = saved
        } else {
            previousState = nil
        }
        let bufferedItems = previousState?.bufferedItems ?? []
        let partitionCursors = previousState?.partitionCursors ?? [:]
        let pending: [(AgentMemoryPartition, String?)]
        if bufferedItems.count >= size {
            pending = []
        } else if previousState == nil {
            pending = AgentMemoryPartition.allCases.map { ($0, nil) }
        } else {
            pending = AgentMemoryPartition.allCases.compactMap { partition in
                partitionCursors[partition].map { (partition, Optional($0)) }
            }
        }
        let pages = await AgentToolBatchScheduler(maximumConcurrency: 2).run(pending) { entry in
            await self.fetch(query, pageSize: size, partition: entry.0, cursor: entry.1)
        }
        let previouslySeen = previousState?.seenItemIDs ?? []
        var batchSeen = previouslySeen
        let merged = (bufferedItems + pages.flatMap(\.page.items))
            .sorted { lhs, rhs in lhs.eventTime == rhs.eventTime ? lhs.id < rhs.id : lhs.eventTime > rhs.eventTime }
            .filter { batchSeen.insert($0.id).inserted }
        var nextCursors = partitionCursors
        for result in pages { nextCursors[result.partition] = nil }
        nextCursors.merge(Dictionary(uniqueKeysWithValues: pages.compactMap { result in
            result.page.nextCursor.map { (result.partition, $0) }
        })) { _, replacement in replacement }
        let pageItems = Array(merged.prefix(size))
        let remainingItems = Array(merged.dropFirst(pageItems.count))
        var returnedItemIDs = previouslySeen
        returnedItemIDs.formUnion(pageItems.map(\.id))
        let nextPage = nextCursors.isEmpty && remainingItems.isEmpty ? nil : UUID().uuidString
        if let nextPage {
            cursors[nextPage] = CursorState(
                query: query,
                pageSize: size,
                partitionCursors: nextCursors,
                bufferedItems: remainingItems,
                seenItemIDs: returnedItemIDs
            )
        }
        let visible = pageItems.map { item in
            var redacted = item
            redacted.provenance = nil
            return redacted
        }
        return AgentMemoryQueryPage(items: Array(visible), nextPage: nextPage, errors: pages.compactMap(\.error))
    }

    private struct PartitionResult: Sendable {
        var partition: AgentMemoryPartition
        var page: AgentMemoryPartitionPage
        var error: String?
    }

    private func fetch(_ query: String, pageSize: Int, partition: AgentMemoryPartition, cursor: String?) async -> PartitionResult {
        do {
            return PartitionResult(
                partition: partition,
                page: try await provider.query(.init(query: query, pageSize: pageSize, cursor: cursor), partition: partition),
                error: nil
            )
        } catch {
            return PartitionResult(partition: partition, page: AgentMemoryPartitionPage(items: []), error: String(describing: error))
        }
    }
}

public struct AgentEvidenceState: Codable, Sendable, Equatable {
    public var conclusions: [String]
    public var references: [AgentStrategyEvidenceReference]
    public var conflicts: [String]
    public var unresolvedQuestions: [String]
    public var seenQuerySignatures: Set<String>

    public init(conclusions: [String] = [], references: [AgentStrategyEvidenceReference] = [], conflicts: [String] = [], unresolvedQuestions: [String] = [], seenQuerySignatures: Set<String> = []) {
        self.conclusions = conclusions
        self.references = references
        self.conflicts = conflicts
        self.unresolvedQuestions = unresolvedQuestions
        self.seenQuerySignatures = seenQuerySignatures
    }

    public mutating func recordQuery(_ signature: String, producedNewEvidence: Bool) -> Bool {
        let normalized = signature.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, seenQuerySignatures.insert(normalized).inserted else { return false }
        return producedNewEvidence
    }

    public mutating func merge(_ other: Self) {
        conclusions = stableUnion(conclusions, other.conclusions)
        references = stableUnion(references, other.references, key: { $0.uri ?? $0.id })
        conflicts = stableUnion(conflicts, other.conflicts)
        unresolvedQuestions = stableUnion(unresolvedQuestions, other.unresolvedQuestions)
        seenQuerySignatures.formUnion(other.seenQuerySignatures)
    }

    @discardableResult
    public mutating func ingestExternalResearchPayload(_ payload: String) -> Int {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = object["results"] as? [[String: Any]] else { return 0 }
        var knownReferences = Set(references.map { $0.uri ?? $0.id })
        var added = 0
        for raw in rawItems {
            guard raw["error"] == nil else { continue }
            let id = raw["id"] as? String ?? "evidence-\(references.count + added + 1)"
            let uri = raw["uri"] as? String ?? (raw["citations"] as? [String])?.first
            let summary = (raw["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard uri != nil || !summary.isEmpty else { continue }
            let identity = uri ?? id
            guard knownReferences.insert(identity).inserted else { continue }
            references.append(.init(id: id, uri: uri, claim: summary))
            if !summary.isEmpty, !conclusions.contains(summary) { conclusions.append(summary) }
            added += 1
        }
        return added
    }

    public var compactPrompt: String {
        let conclusionText = conclusions.suffix(12).map { "- \($0)" }.joined(separator: "\n")
        let referenceText = references.suffix(20).map { reference in
            "- [\(reference.id)] \(reference.uri ?? "no-uri"): \(reference.claim)"
        }.joined(separator: "\n")
        let conflictText = conflicts.suffix(8).map { "- \($0)" }.joined(separator: "\n")
        let unresolvedText = unresolvedQuestions.suffix(8).map { "- \($0)" }.joined(separator: "\n")
        return """
        Compressed research evidence retained by the trusted runtime.
        Conclusions:
        \(conclusionText.isEmpty ? "- none" : conclusionText)
        References:
        \(referenceText.isEmpty ? "- none" : referenceText)
        Conflicts:
        \(conflictText.isEmpty ? "- none" : conflictText)
        Unresolved questions:
        \(unresolvedText.isEmpty ? "- none" : unresolvedText)
        """
    }

    private func stableUnion(_ lhs: [String], _ rhs: [String]) -> [String] { stableUnion(lhs, rhs, key: { $0 }) }
    private func stableUnion<T>(_ lhs: [T], _ rhs: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return (lhs + rhs).filter { seen.insert(key($0)).inserted }
    }
}

public struct AgentLoopRecoveryState: Codable, Sendable, Equatable {
    public var phase: AgentLoopPhase
    public var activeModuleIDs: [AgentPromptModuleID]
    public var evidenceState: AgentEvidenceState

    public init(phase: AgentLoopPhase, activeModuleIDs: [AgentPromptModuleID], evidenceState: AgentEvidenceState) {
        self.phase = phase
        self.activeModuleIDs = activeModuleIDs
        self.evidenceState = evidenceState
    }

    public var trustedPrompt: String {
        let modules = activeModuleIDs.map(\.rawValue).joined(separator: ", ")
        return """
        Trusted context recovery state:
        - phase: \(phase.rawValue)
        - active Prompt Modules: \(modules)

        \(evidenceState.compactPrompt)
        """
    }
}

public struct AgentPhasedLoopState: Sendable, Equatable {
    public private(set) var phase: AgentLoopPhase = .strategyResearch
    public private(set) var strategy: AgentStrategyPlan?
    public var activeModuleIDs: [AgentPromptModuleID] = []
    public var evidenceState = AgentEvidenceState()

    public init() {}

    public mutating func commitStrategy(_ plan: AgentStrategyPlan, memoryCapabilityAvailable: Bool) throws {
        guard phase == .strategyResearch else {
            throw AgentStrategyPlanValidationError.invalidCommitPhase(phase)
        }
        try AgentStrategyPlanValidator().validate(plan, memoryCapabilityAvailable: memoryCapabilityAvailable)
        strategy = plan
        phase = plan.memoryDecision == .query ? .memoryPreparation : .taskExecution
    }

    public mutating func completeMemoryPreparation() { if phase == .memoryPreparation { phase = .taskExecution } }
    public mutating func prepareFinalOutput() { if phase == .taskExecution { phase = .finalSynthesis } }
    public mutating func resumeMemoryPreparation() { phase = .memoryPreparation }
    public mutating func resumeResearch() { phase = .strategyResearch }
    public var recoveryState: AgentLoopRecoveryState { .init(phase: phase, activeModuleIDs: activeModuleIDs, evidenceState: evidenceState) }
}

public struct AgentPromptCacheContext: Codable, Sendable, Equatable {
    public var phase: AgentLoopPhase
    public var promptVersion: String
    public var stableToolBundleVersion: String
    public var explicitBreakpointIndex: Int?

    public init(phase: AgentLoopPhase, promptVersion: String, stableToolBundleVersion: String, explicitBreakpointIndex: Int? = nil) {
        self.phase = phase
        self.promptVersion = promptVersion
        self.stableToolBundleVersion = stableToolBundleVersion
        self.explicitBreakpointIndex = explicitBreakpointIndex
    }
}

public enum AgentPhaseToolContract {
    public static let commitStrategyName = "agent_commit_strategy"
    public static let activateModuleName = "prompt_module_activate"
    public static let prepareFinalOutputName = "prepare_final_output"
    public static let externalSearchBatchName = "external_research_search_batch"
    public static let externalReadBatchName = "external_research_read_batch"
    public static let memoryQueryName = "memory_query"

    public static let definitions: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: commitStrategyName,
            description: "Commit the structured strategy, Prompt Modules, and Memory decision after research is sufficient.",
            inputSchema: .object(properties: [
                "provisionalApproach": .string(description: "Approach formed from model knowledge before external research."),
                "recommendedApproach": .string(description: "Final approach after comparing evidence."),
                "alternatives": .array(items: .object(properties: ["approach": .string(description: ""), "tradeoffs": .string(description: "")], required: ["approach", "tradeoffs"]), description: ""),
                "constraints": .array(items: .string(description: ""), description: ""),
                "evidenceReferences": .array(items: .object(properties: ["id": .string(description: ""), "uri": .string(description: ""), "claim": .string(description: "")], required: ["id", "claim"]), description: ""),
                "unresolvedQuestions": .array(items: .string(description: ""), description: ""),
                "taskMode": .stringEnumeration(values: AgentStrategyTaskMode.allRawValues, description: ""),
                "requestedModuleIDs": .array(items: .string(description: ""), description: ""),
                "memoryDecision": .object(properties: [
                    "action": .stringEnumeration(values: ["query", "skip"], description: "Query Memory or skip only for an enumerated Memory-specific exception."),
                    "reason": .stringEnumeration(values: AgentMemorySkipReason.allRawValues, description: "Reason for skipping Memory. memoryCapabilityUnavailable refers only to the runtime Memory tools, never image generation or another task capability.")
                ], required: ["action"]),
                "memoryQueries": .array(items: .string(description: ""), description: ""),
                "memoryPageSize": .integer(description: "1...100; defaults to 20.")
            ], required: ["provisionalApproach", "recommendedApproach", "taskMode", "memoryDecision"])
        ),
        AgentToolDefinition(
            name: activateModuleName,
            description: "Activate trusted Prompt Modules by Catalog ID. The runtime validates IDs, capabilities, and dependencies.",
            inputSchema: .object(properties: ["moduleIDs": .array(items: .string(description: ""), description: "")], required: ["moduleIDs"])
        ),
        AgentToolDefinition(
            name: prepareFinalOutputName,
            description: "Enter Final Synthesis and internally finish final-response Profile pagination before generating a non-mechanical final output.",
            inputSchema: .object(properties: ["reason": .string(description: "")], required: ["reason"])
        ),
        AgentToolDefinition(
            name: externalSearchBatchName,
            description: "Batch discovery across read-only Web, MCP, and knowledge sources. Returns summaries only after every item reaches a terminal state.",
            inputSchema: .object(properties: ["requests": .array(items: .object(properties: ["sourceID": .string(description: ""), "query": .string(description: ""), "cursor": .string(description: "")], required: ["sourceID", "query"]), description: "")], required: ["requests"])
        ),
        AgentToolDefinition(
            name: externalReadBatchName,
            description: "Batch deep-read selected original resources. Returns selected content after every item reaches a terminal state.",
            inputSchema: .object(properties: ["requests": .array(items: .object(properties: ["sourceID": .string(description: ""), "uri": .string(description: ""), "selection": .string(description: "")], required: ["sourceID", "uri"]), description: "")], required: ["requests"])
        ),
        AgentToolDefinition(
            name: memoryQueryName,
            description: "Query Memory using an LLM-authored query. Runtime searches recent and long-term partitions concurrently, merges and deduplicates them, and returns newest events first without exposing partitions.",
            inputSchema: .object(properties: ["query": .string(description: ""), "pageSize": .integer(description: ""), "page": .string(description: "")], required: ["query"])
        )
    ].sorted { $0.name < $1.name }
}

private extension AgentStrategyTaskMode {
    static var allRawValues: [String] { [mechanical, coding, research, creative, recommendation, general].map(\.rawValue) }
}

private extension AgentMemorySkipReason {
    static var allRawValues: [String] {
        [userExplicitlyDisabled, mechanicalTextTransformation, deterministicComputationWithCompleteInput, historyIndependentMechanicalOrCodingTask].map(\.rawValue)
    }
}

public enum AgentStrategyPlanDecoder {
    public static func decode(argumentsJSON: String) throws -> AgentStrategyPlan {
        let data = Data(argumentsJSON.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(AgentStrategyPlan.self, from: data)
    }
}
