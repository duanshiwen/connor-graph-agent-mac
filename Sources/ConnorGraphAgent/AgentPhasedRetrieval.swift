import Foundation
import ConnorGraphCore

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
    case production
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
    public var memoryDecision: AgentStrategyMemoryDecision
    public var memoryQueries: [String]
    public var memoryPageSize: Int
    public var deliverables: [String]
    public var acceptanceCriteria: [String]
    public var verificationSteps: [String]

    public init(
        provisionalApproach: String,
        recommendedApproach: String,
        alternatives: [AgentStrategyAlternative] = [],
        constraints: [String] = [],
        evidenceReferences: [AgentStrategyEvidenceReference] = [],
        unresolvedQuestions: [String] = [],
        taskMode: AgentStrategyTaskMode,
        memoryDecision: AgentStrategyMemoryDecision,
        memoryQueries: [String] = [],
        memoryPageSize: Int = 20,
        deliverables: [String] = [],
        acceptanceCriteria: [String] = [],
        verificationSteps: [String] = []
    ) {
        self.provisionalApproach = provisionalApproach
        self.recommendedApproach = recommendedApproach
        self.alternatives = alternatives
        self.constraints = constraints
        self.evidenceReferences = evidenceReferences
        self.unresolvedQuestions = unresolvedQuestions
        self.taskMode = taskMode
        self.memoryDecision = memoryDecision
        self.memoryQueries = memoryQueries
        self.memoryPageSize = memoryPageSize
        self.deliverables = deliverables
        self.acceptanceCriteria = acceptanceCriteria
        self.verificationSteps = verificationSteps
    }

    private enum CodingKeys: String, CodingKey {
        case provisionalApproach, recommendedApproach, alternatives, constraints, evidenceReferences
        case unresolvedQuestions, taskMode, memoryDecision, memoryQueries, memoryPageSize
        case deliverables, acceptanceCriteria, verificationSteps
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
        memoryDecision = try container.decode(AgentStrategyMemoryDecision.self, forKey: .memoryDecision)
        memoryQueries = try container.decodeIfPresent([String].self, forKey: .memoryQueries) ?? []
        memoryPageSize = try container.decodeIfPresent(Int.self, forKey: .memoryPageSize) ?? 20
        deliverables = try container.decodeIfPresent([String].self, forKey: .deliverables) ?? []
        acceptanceCriteria = try container.decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? []
        verificationSteps = try container.decodeIfPresent([String].self, forKey: .verificationSteps) ?? []
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
    case productionDeliverablesRequired
    case productionAcceptanceCriteriaRequired
    case productionVerificationStepsRequired
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
        if plan.taskMode == .production {
            guard !normalizedItems(plan.deliverables).isEmpty else {
                throw AgentStrategyPlanValidationError.productionDeliverablesRequired
            }
            guard !normalizedItems(plan.acceptanceCriteria).isEmpty else {
                throw AgentStrategyPlanValidationError.productionAcceptanceCriteriaRequired
            }
            guard !normalizedItems(plan.verificationSteps).isEmpty else {
                throw AgentStrategyPlanValidationError.productionVerificationStepsRequired
            }
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

    private func normalizedItems(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public enum AgentDeliveryReviewOutcome: String, Codable, Sendable, Equatable {
    case passed
    case partial
    case blocked
}

public enum AgentDeliveryCriterionStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case notVerified = "not_verified"
}

public struct AgentDeliveryCriterionReview: Codable, Sendable, Equatable {
    public var criterion: String
    public var status: AgentDeliveryCriterionStatus
    public var evidence: String

    public init(criterion: String, status: AgentDeliveryCriterionStatus, evidence: String) {
        self.criterion = criterion
        self.status = status
        self.evidence = evidence
    }
}

public struct AgentDeliveryVerificationReview: Codable, Sendable, Equatable {
    public var method: String
    public var evidence: String

    public init(method: String, evidence: String) {
        self.method = method
        self.evidence = evidence
    }
}

public struct AgentDeliveryReview: Codable, Sendable, Equatable {
    public var outcome: AgentDeliveryReviewOutcome
    public var deliverables: [String]
    public var criteria: [AgentDeliveryCriterionReview]
    public var verification: [AgentDeliveryVerificationReview]
    public var remainingIssues: [String]

    public init(
        outcome: AgentDeliveryReviewOutcome,
        deliverables: [String],
        criteria: [AgentDeliveryCriterionReview],
        verification: [AgentDeliveryVerificationReview],
        remainingIssues: [String] = []
    ) {
        self.outcome = outcome
        self.deliverables = deliverables
        self.criteria = criteria
        self.verification = verification
        self.remainingIssues = remainingIssues
    }
}

public struct AgentFinalOutputPreparation: Codable, Sendable, Equatable {
    public var reason: String
    public var deliveryReview: AgentDeliveryReview?

    public init(reason: String, deliveryReview: AgentDeliveryReview? = nil) {
        self.reason = reason
        self.deliveryReview = deliveryReview
    }
}

public enum AgentDeliveryReviewValidationError: Error, Sendable, Equatable {
    case reviewRequired
    case deliverableCoverageIncomplete
    case criterionCoverageIncomplete
    case verificationCoverageIncomplete
    case evidenceRequired
    case passedReviewContainsFailure
    case passedReviewContainsRemainingIssues
    case incompleteReviewNeedsRemainingIssue
}

public struct AgentDeliveryReviewValidator: Sendable {
    public init() {}

    public func validate(
        _ review: AgentDeliveryReview?,
        for plan: AgentStrategyPlan,
        artifactWasProduced: Bool = false
    ) throws {
        guard plan.taskMode == .production || artifactWasProduced else { return }
        guard let review else { throw AgentDeliveryReviewValidationError.reviewRequired }

        let plannedDeliverables = normalizedSet(plan.deliverables)
        let reviewedDeliverables = normalizedSet(review.deliverables)
        guard !reviewedDeliverables.isEmpty,
              plannedDeliverables.isSubset(of: reviewedDeliverables) else {
            throw AgentDeliveryReviewValidationError.deliverableCoverageIncomplete
        }

        let criteriaByName = Dictionary(review.criteria.map {
            (normalize($0.criterion), $0)
        }, uniquingKeysWith: { first, _ in first })
        guard !criteriaByName.isEmpty,
              normalizedSet(plan.acceptanceCriteria).isSubset(of: Set(criteriaByName.keys)) else {
            throw AgentDeliveryReviewValidationError.criterionCoverageIncomplete
        }
        let verificationByMethod = Dictionary(review.verification.map {
            (normalize($0.method), $0)
        }, uniquingKeysWith: { first, _ in first })
        guard !verificationByMethod.isEmpty,
              normalizedSet(plan.verificationSteps).isSubset(of: Set(verificationByMethod.keys)) else {
            throw AgentDeliveryReviewValidationError.verificationCoverageIncomplete
        }
        guard review.criteria.allSatisfy({ !normalize($0.evidence).isEmpty }),
              review.verification.allSatisfy({ !normalize($0.evidence).isEmpty }) else {
            throw AgentDeliveryReviewValidationError.evidenceRequired
        }

        switch review.outcome {
        case .passed:
            guard review.criteria.allSatisfy({ $0.status == .passed }) else {
                throw AgentDeliveryReviewValidationError.passedReviewContainsFailure
            }
            guard normalizedSet(review.remainingIssues).isEmpty else {
                throw AgentDeliveryReviewValidationError.passedReviewContainsRemainingIssues
            }
        case .partial, .blocked:
            guard !normalizedSet(review.remainingIssues).isEmpty else {
                throw AgentDeliveryReviewValidationError.incompleteReviewNeedsRemainingIssue
            }
        }
    }

    private func normalizedSet(_ values: [String]) -> Set<String> {
        Set(values.map(normalize).filter { !$0.isEmpty })
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum AgentProductionToolClassifier {
    public static func producesArtifact(
        toolName: String,
        permission: AgentPermissionCapability?
    ) -> Bool {
        switch permission {
        case .writeWorkspaceFile, .editWorkspaceFile, .createInteractiveWebDraft, .createMailDraft:
            return true
        default:
            break
        }
        let normalized = toolName.lowercased()
        if normalized == "generate_image"
            || normalized == "edit_image"
            || normalized == "applypatch"
            || normalized == "apply_patch"
            || normalized == "write"
            || normalized == "edit"
            || normalized.hasPrefix("connor_skill_create")
            || normalized.hasPrefix("connor_skill_update")
            || normalized.hasPrefix("interactive_web_create_draft")
        {
            return true
        }
        let productionNouns = [
            "artifact", "document", "docx", "presentation", "slides",
            "spreadsheet", "workbook", "image", "website", "webpage"
        ]
        let productionVerbs = ["create", "generate", "edit", "update", "write", "export"]
        return productionNouns.contains(where: normalized.contains)
            && productionVerbs.contains(where: normalized.contains)
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
    public var evidenceState: AgentEvidenceState

    public init(phase: AgentLoopPhase, evidenceState: AgentEvidenceState) {
        self.phase = phase
        self.evidenceState = evidenceState
    }

    public var trustedPrompt: String {
        return """
        Trusted context recovery state:
        - phase: \(phase.rawValue)

        \(evidenceState.compactPrompt)
        """
    }
}

public struct AgentPhasedLoopState: Sendable, Equatable {
    public private(set) var phase: AgentLoopPhase = .strategyResearch
    public private(set) var strategy: AgentStrategyPlan?
    public var evidenceState = AgentEvidenceState()

    public init() {}

    public mutating func commitStrategy(_ plan: AgentStrategyPlan, memoryCapabilityAvailable: Bool) throws {
        guard phase == .strategyResearch else {
            throw AgentStrategyPlanValidationError.invalidCommitPhase(phase)
        }
        try AgentStrategyPlanValidator().validate(
            plan,
            memoryCapabilityAvailable: memoryCapabilityAvailable
        )
        strategy = plan
        phase = plan.memoryDecision == .query ? .memoryPreparation : .taskExecution
    }

    public mutating func completeMemoryPreparation() { if phase == .memoryPreparation { phase = .taskExecution } }
    public mutating func prepareFinalOutput() { if phase == .taskExecution { phase = .finalSynthesis } }
    public mutating func invalidateFinalOutput() { if phase == .finalSynthesis { phase = .taskExecution } }
    public mutating func resumeMemoryPreparation() { phase = .memoryPreparation }
    public mutating func resumeResearch() { phase = .strategyResearch }
    public mutating func convergeToFinalSynthesis() { phase = .finalSynthesis }
    public var recoveryState: AgentLoopRecoveryState { .init(phase: phase, evidenceState: evidenceState) }
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
    public static let prepareFinalOutputName = "prepare_final_output"
    public static let externalSearchBatchName = "parallel_tool_query"
    public static let externalReadBatchName = "parallel_tool_execute"
    public static let memoryQueryName = "memory_query"

    public static let definitions: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: commitStrategyName,
            description: "Commit the structured strategy and Memory decision after research is sufficient.",
            inputSchema: .object(properties: [
                "provisionalApproach": .string(description: "Approach formed from model knowledge before external research."),
                "recommendedApproach": .string(description: "Final approach after comparing evidence."),
                "alternatives": .array(items: .object(properties: ["approach": .string(description: ""), "tradeoffs": .string(description: "")], required: ["approach", "tradeoffs"]), description: ""),
                "constraints": .array(items: .string(description: ""), description: ""),
                "evidenceReferences": .array(items: .object(properties: ["id": .string(description: ""), "uri": .string(description: ""), "claim": .string(description: "")], required: ["id", "claim"]), description: ""),
                "unresolvedQuestions": .array(items: .string(description: ""), description: ""),
                "taskMode": .stringEnumeration(values: AgentStrategyTaskMode.allRawValues, description: ""),
                "memoryDecision": .object(properties: [
                    "action": .stringEnumeration(values: ["query", "skip"], description: "Query Memory or skip only for an enumerated Memory-specific exception."),
                    "reason": .stringEnumeration(values: AgentMemorySkipReason.allRawValues, description: "Reason for skipping Memory; required when action is skip.")
                ], required: ["action"]),
                "memoryQueries": .array(items: .string(description: ""), description: ""),
                "memoryPageSize": .integer(description: "1...100; defaults to 20."),
                "deliverables": .array(items: .string(description: "Exact deliverable"), description: "Required when taskMode is production."),
                "acceptanceCriteria": .array(items: .string(description: "Observable acceptance criterion"), description: "Required when taskMode is production."),
                "verificationSteps": .array(items: .string(description: "Concrete final verification method"), description: "Required when taskMode is production.")
            ], required: ["provisionalApproach", "recommendedApproach", "taskMode", "memoryDecision"])
        ),
        AgentToolDefinition(
            name: prepareFinalOutputName,
            description: "Enter Final Synthesis and internally finish final-response Profile pagination only after the requested work, proportionate verification, and the required final attention batch are complete. Production tasks must include a deliveryReview that covers every committed deliverable, acceptance criterion, and verification step with concrete evidence; report partial or blocked instead of claiming success when issues remain. Call once, then return the final answer unless the profile exposes a concrete issue that changes the result. This control tool does not itself read mail, calendars, RSS, or other sources.",
            inputSchema: .object(properties: [
                "reason": .string(description: "Why task execution is ready to enter final synthesis."),
                "deliveryReview": .object(properties: [
                    "outcome": .stringEnumeration(values: ["passed", "partial", "blocked"], description: "Overall delivery outcome."),
                    "deliverables": .array(items: .string(description: "Completed deliverable"), description: "Every deliverable committed in the production strategy."),
                    "criteria": .array(items: .object(properties: [
                        "criterion": .string(description: "Exact acceptance criterion from the production strategy."),
                        "status": .stringEnumeration(values: ["passed", "failed", "not_verified"], description: "Observed criterion status."),
                        "evidence": .string(description: "Concrete observation, tool result, check, or inspection evidence.")
                    ], required: ["criterion", "status", "evidence"]), description: "One result for every committed acceptance criterion."),
                    "verification": .array(items: .object(properties: [
                        "method": .string(description: "Exact verification step from the production strategy."),
                        "evidence": .string(description: "Concrete verification result; never merely 'checked'.")
                    ], required: ["method", "evidence"]), description: "One result for every committed verification step."),
                    "remainingIssues": .array(items: .string(description: "Known remaining issue"), description: "Must be empty for passed and non-empty for partial or blocked.")
                ], required: ["outcome", "deliverables", "criteria", "verification", "remainingIssues"])
            ], required: ["reason"])
        ),
        AgentToolDefinition(
            name: externalSearchBatchName,
            description: "Run model-selected independent native reads concurrently and return one aggregated result. This wrapper does not classify call semantics; native tool permissions remain authoritative. Put every read that can be anticipated from current evidence into this one batch. Each calls item uses the exact native toolName and native arguments object. Do not repeat a completed call unless an intervening state change or explicit retry instruction makes the same call necessary.",
            inputSchema: .object(properties: [
                "calls": .array(items: .object(properties: [
                    "toolName": .string(description: "Exact native tool name selected by the model."),
                    "arguments": .object(properties: [:], required: [])
                ], required: ["toolName", "arguments"]), description: "Independent native read calls to execute concurrently."),
                "excludedToolNames": .array(items: .string(description: "Exact tool name that must not execute in this batch."), description: "A call that conflicts with this list is rejected.")
            ], required: ["calls"])
        ),
        AgentToolDefinition(
            name: externalReadBatchName,
            description: "Run model-selected native action calls as one ordered batch and return one aggregated result. Put every currently determined compatible action into this one batch. Each calls item uses the exact native toolName and native arguments object. Calls execute in listed order through normal permission and approval handling; never repeat a successful mutation merely to confirm it.",
            inputSchema: .object(properties: [
                "calls": .array(items: .object(properties: [
                    "toolName": .string(description: "Exact native tool name selected by the model."),
                    "arguments": .object(properties: [:], required: [])
                ], required: ["toolName", "arguments"]), description: "Native mutation calls to execute in listed order."),
                "excludedToolNames": .array(items: .string(description: "Exact tool name that must not execute in this batch."), description: "A call that conflicts with this list is rejected.")
            ], required: ["calls"])
        ),
        AgentToolDefinition(
            name: memoryQueryName,
            description: "Query Memory using an LLM-authored query. Runtime searches recent and long-term partitions concurrently, merges and deduplicates them, and returns newest events first without exposing partitions.",
            inputSchema: .object(properties: ["query": .string(description: ""), "pageSize": .integer(description: ""), "page": .string(description: "")], required: ["query"])
        )
    ].sorted { $0.name < $1.name }
}

private extension AgentStrategyTaskMode {
    static var allRawValues: [String] { [mechanical, coding, production, research, creative, recommendation, general].map(\.rawValue) }
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

public enum AgentFinalOutputPreparationDecoder {
    public static func decode(argumentsJSON: String) throws -> AgentFinalOutputPreparation {
        try JSONDecoder().decode(AgentFinalOutputPreparation.self, from: Data(argumentsJSON.utf8))
    }
}
