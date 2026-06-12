import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphStore

public enum GraphMemoryProductCardKind: String, Codable, Sendable, Equatable {
    case writeCandidate
    case admissionHold
    case changeLog
    case contextUse
    case feedbackSignal
    case distillationCandidate
}

public enum GraphMemoryProductSeverity: String, Codable, Sendable, Equatable {
    case info
    case success
    case needsReview
    case warning
    case error
}

public struct GraphMemoryDashboardSummary: Codable, Sendable, Equatable {
    public var pendingCandidateCount: Int
    public var openHoldCount: Int
    public var recentChangeCount: Int
    public var contextItemCount: Int
    public var feedbackSignalCount: Int
    public var stagedBundleCount: Int
    public var distillationCandidateCount: Int
    public var contextReady: Bool
    public var ingestionReady: Bool
    public var distillationReady: Bool
    public var reviewReady: Bool

    public init(
        pendingCandidateCount: Int,
        openHoldCount: Int,
        recentChangeCount: Int,
        contextItemCount: Int = 0,
        feedbackSignalCount: Int = 0,
        stagedBundleCount: Int = 0,
        distillationCandidateCount: Int = 0,
        contextReady: Bool = false,
        ingestionReady: Bool = false,
        distillationReady: Bool = false,
        reviewReady: Bool = true
    ) {
        self.pendingCandidateCount = pendingCandidateCount
        self.openHoldCount = openHoldCount
        self.recentChangeCount = recentChangeCount
        self.contextItemCount = contextItemCount
        self.feedbackSignalCount = feedbackSignalCount
        self.stagedBundleCount = stagedBundleCount
        self.distillationCandidateCount = distillationCandidateCount
        self.contextReady = contextReady
        self.ingestionReady = ingestionReady
        self.distillationReady = distillationReady
        self.reviewReady = reviewReady
    }
}

public struct GraphMemoryProductCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: GraphMemoryProductCardKind
    public var title: String
    public var detail: String
    public var severity: GraphMemoryProductSeverity
    public var sourceIDs: [String]
    public var recommendedActions: [String]
    public var createdAt: Date

    public init(
        id: String,
        kind: GraphMemoryProductCardKind,
        title: String,
        detail: String,
        severity: GraphMemoryProductSeverity,
        sourceIDs: [String] = [],
        recommendedActions: [String] = [],
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.severity = severity
        self.sourceIDs = sourceIDs
        self.recommendedActions = recommendedActions
        self.createdAt = createdAt
    }
}

public struct GraphMemoryReviewActionResult: Sendable, Equatable {
    public var candidate: GraphWriteCandidate
    public var card: GraphMemoryProductCard
    public var event: AgentEvent
    public var message: String

    public init(candidate: GraphWriteCandidate, card: GraphMemoryProductCard, event: AgentEvent, message: String) {
        self.candidate = candidate
        self.card = card
        self.event = event
        self.message = message
    }
}

public enum GraphMemoryProductizationError: Error, Sendable, Equatable, CustomStringConvertible {
    case candidateNotFound(String)

    public var description: String {
        switch self {
        case .candidateNotFound(let id): "candidateNotFound: \(id)"
        }
    }
}

public struct GraphMemoryDashboard: Sendable, Equatable {
    public var summary: GraphMemoryDashboardSummary
    public var cards: [GraphMemoryProductCard]

    public init(summary: GraphMemoryDashboardSummary, cards: [GraphMemoryProductCard]) {
        self.summary = summary
        self.cards = cards
    }
}

public struct GraphMemoryRetrievalExplanationCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind.rawValue):\(memoryID)" }
    public var rank: Int
    public var kind: GraphIndexOwnerType
    public var memoryID: String
    public var title: String
    public var excerpt: String
    public var score: Double
    public var scoreLabel: String
    public var retrievalMethod: String
    public var why: String
    public var evidenceEpisodeIDs: [String]
    public var metadata: [String: String]

    public init(rank: Int, hit: GraphSearchHit) {
        self.rank = rank
        self.kind = hit.ownerType
        self.memoryID = hit.ownerID
        self.title = hit.title
        self.excerpt = hit.text
        self.score = hit.score
        self.scoreLabel = "\(Int((hit.score * 100).rounded()))%"
        self.retrievalMethod = hit.retrievalMethod
        self.evidenceEpisodeIDs = hit.sourceEpisodeIDs
        self.metadata = hit.metadata
        let evidence = hit.sourceEpisodeIDs.isEmpty ? "no linked episode evidence" : "episode evidence: \(hit.sourceEpisodeIDs.joined(separator: ", "))"
        let belief = hit.metadata["belief_status"].map { "belief: \($0)" } ?? "belief: unknown"
        self.why = "Rank \(rank) because \(hit.retrievalMethod) returned score \(self.scoreLabel); \(belief); \(evidence)."
    }
}

public struct GraphMemoryRetrievalExplanation: Sendable, Equatable {
    public var queryText: String
    public var summary: String
    public var cards: [GraphMemoryRetrievalExplanationCard]

    public init(queryText: String, summary: String, cards: [GraphMemoryRetrievalExplanationCard]) {
        self.queryText = queryText
        self.summary = summary
        self.cards = cards
    }
}

public struct GraphMemoryRetrievalExplainer: Sendable {
    public init() {}

    public func explain(query: GraphSearchQuery, response: GraphSearchResponse) -> GraphMemoryRetrievalExplanation {
        let cards = response.hits.enumerated().map { index, hit in
            GraphMemoryRetrievalExplanationCard(rank: index + 1, hit: hit)
        }
        let summary = "\(cards.count) graph memory hit\(cards.count == 1 ? "" : "s") for query '\(query.text)' using graph \(query.graphID)."
        return GraphMemoryRetrievalExplanation(queryText: query.text, summary: summary, cards: cards)
    }
}

public struct GraphMemoryProductizationCenter: Sendable {
    public var candidateRepository: AppGraphWriteCandidateRepository
    public var holdQueueRepository: AppGraphAdmissionHoldQueueRepository
    public var changeLogRepository: AppGraphMemoryChangeLogRepository

    public init(
        candidateRepository: AppGraphWriteCandidateRepository,
        holdQueueRepository: AppGraphAdmissionHoldQueueRepository,
        changeLogRepository: AppGraphMemoryChangeLogRepository
    ) {
        self.candidateRepository = candidateRepository
        self.holdQueueRepository = holdQueueRepository
        self.changeLogRepository = changeLogRepository
    }

    public func approveCandidate(id: String, sessionID: String, actor: String = "human-reviewer") async throws -> GraphMemoryReviewActionResult {
        let candidate = try requireCandidate(id)
        let approved = try await candidateRepository.approveGoverned(candidate, actor: actor)
        let message = "Graph memory candidate \(id) approved and remains governed before commit."
        let event = AgentEvent.graphMemoryHeld(AgentGraphMemoryLifecycleEvent(
            runID: approved.proposedByRunID,
            sessionID: sessionID,
            memoryID: approved.id,
            message: message
        ))
        return GraphMemoryReviewActionResult(candidate: approved, card: card(for: approved), event: event, message: message)
    }

    public func rejectCandidate(id: String, sessionID: String, reason: String, actor: String = "human-reviewer") async throws -> GraphMemoryReviewActionResult {
        let candidate = try requireCandidate(id)
        let rejected = try await candidateRepository.rejectGoverned(candidate, reason: reason, actor: actor)
        let message = "Graph memory candidate \(id) rejected: \(reason)"
        let event = AgentEvent.graphMemoryHeld(AgentGraphMemoryLifecycleEvent(
            runID: rejected.proposedByRunID,
            sessionID: sessionID,
            memoryID: rejected.id,
            message: message
        ))
        return GraphMemoryReviewActionResult(candidate: rejected, card: card(for: rejected), event: event, message: message)
    }

    public func loadDashboard(limit: Int = 50) throws -> GraphMemoryDashboard {
        let pendingCandidates = try candidateRepository.loadCandidates(status: .pendingReview, limit: limit)
        let failedCandidates = try candidateRepository.loadCandidates(status: .validationFailed, limit: limit)
        let holds = try holdQueueRepository.loadOpenItems(limit: limit)
        let changes = try changeLogRepository.loadRecentEntries(limit: limit)

        var cards: [GraphMemoryProductCard] = []
        cards.append(contentsOf: holds.map(card(for:)))
        cards.append(contentsOf: pendingCandidates.map(card(for:)))
        cards.append(contentsOf: failedCandidates.map(card(for:)))
        cards.append(contentsOf: changes.map(card(for:)))

        return GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(
                pendingCandidateCount: pendingCandidates.count + failedCandidates.count,
                openHoldCount: holds.count,
                recentChangeCount: changes.count,
                reviewReady: true
            ),
            cards: Array(cards.prefix(limit))
        )
    }

    public static func dashboard(
        contextContract: AgentGraphMemoryContextContract? = nil,
        feedbackSignals: [AgentGraphMemoryFeedbackSignal] = [],
        stagingBuffer: MemoryStagingBuffer? = nil,
        distillationResult: MemoryDistillationResult? = nil,
        reviewDashboard: GraphMemoryDashboard? = nil,
        limit: Int = 50
    ) -> GraphMemoryDashboard {
        var cards: [GraphMemoryProductCard] = []
        if let contextContract {
            cards.append(contentsOf: contextContract.items.map { card(for: $0, contract: contextContract) })
        }
        cards.append(contentsOf: feedbackSignals.map(card(for:)))
        if let distillationResult {
            cards.append(contentsOf: distillationResult.proposedCandidates.map { card(for: $0, result: distillationResult) })
        }
        if let reviewDashboard {
            cards.append(contentsOf: reviewDashboard.cards)
        }
        let pendingCandidateCount = reviewDashboard?.summary.pendingCandidateCount ?? 0
        let openHoldCount = reviewDashboard?.summary.openHoldCount ?? 0
        let recentChangeCount = reviewDashboard?.summary.recentChangeCount ?? 0
        let stagedBundleCount = stagingBuffer?.pendingBundles.count ?? 0
        let distillationCandidateCount = distillationResult?.proposedCandidates.count ?? 0
        return GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(
                pendingCandidateCount: pendingCandidateCount,
                openHoldCount: openHoldCount,
                recentChangeCount: recentChangeCount,
                contextItemCount: contextContract?.items.count ?? 0,
                feedbackSignalCount: feedbackSignals.count,
                stagedBundleCount: stagedBundleCount,
                distillationCandidateCount: distillationCandidateCount,
                contextReady: contextContract != nil,
                ingestionReady: stagingBuffer != nil || !feedbackSignals.isEmpty,
                distillationReady: distillationResult != nil,
                reviewReady: reviewDashboard != nil
            ),
            cards: Array(cards.prefix(limit))
        )
    }

    private func requireCandidate(_ id: String) throws -> GraphWriteCandidate {
        if let candidate = try candidateRepository.loadCandidates(status: nil, limit: 1_000).first(where: { $0.id == id }) {
            return candidate
        }
        throw GraphMemoryProductizationError.candidateNotFound(id)
    }

    private func card(for item: AppGraphAdmissionHoldQueuePresentation) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: item.id,
            kind: .admissionHold,
            title: item.title,
            detail: item.detail,
            severity: .needsReview,
            sourceIDs: [],
            recommendedActions: item.recommendedActions.map(\.rawValue),
            createdAt: item.createdAt
        )
    }

    private func card(for candidate: GraphWriteCandidate) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: candidate.id,
            kind: .writeCandidate,
            title: "\(candidate.status.rawValue) · \(candidate.kind.rawValue) · confidence \(String(format: "%.2f", candidate.confidence))",
            detail: candidate.rationale,
            severity: severity(for: candidate),
            sourceIDs: candidate.sourceEpisodeIDs,
            recommendedActions: recommendedActions(for: candidate),
            createdAt: candidate.createdAt
        )
    }

    private func card(for change: AppGraphMemoryChangeLogPresentation) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: change.id,
            kind: .changeLog,
            title: change.title,
            detail: change.detail,
            severity: severity(for: change.action),
            createdAt: change.createdAt
        )
    }

    private func severity(for candidate: GraphWriteCandidate) -> GraphMemoryProductSeverity {
        switch candidate.status {
        case .pendingReview, .pendingValidation:
            return .needsReview
        case .validationFailed, .rejected:
            return .error
        case .approved:
            return .warning
        case .committed:
            return .success
        case .superseded:
            return .info
        }
    }

    private func recommendedActions(for candidate: GraphWriteCandidate) -> [String] {
        switch candidate.status {
        case .pendingReview:
            return ["validate", "approve", "reject", "commit_governed"]
        case .validationFailed:
            return ["inspect_errors", "rerun_extraction", "reject"]
        default:
            return []
        }
    }

    private static func card(for item: AgentGraphMemoryContextItem, contract: AgentGraphMemoryContextContract) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: "context-\(item.sourceID)",
            kind: .contextUse,
            title: "\(item.role.rawValue) · \(item.sourceID)",
            detail: "\(item.reason) · \(item.scoreLabel) · \(item.content)",
            severity: item.role == .risk || item.role == .openQuestion ? .needsReview : .info,
            sourceIDs: item.evidenceEpisodeIDs,
            recommendedActions: ["cite_memory", "inspect_source", "check_conflicts"],
            createdAt: contract.generatedAt
        )
    }

    private static func card(for signal: AgentGraphMemoryFeedbackSignal) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: signal.id,
            kind: .feedbackSignal,
            title: "\(signal.trigger.rawValue) · \(signal.candidateKind)",
            detail: signal.rationale,
            severity: signal.highValue || signal.explicitRemember ? .needsReview : .info,
            recommendedActions: ["distill", "inspect_buffer"],
            createdAt: signal.createdAt
        )
    }

    private static func card(for candidate: MemoryDistillationCandidate, result: MemoryDistillationResult) -> GraphMemoryProductCard {
        GraphMemoryProductCard(
            id: candidate.id,
            kind: .distillationCandidate,
            title: "\(candidate.kind.rawValue) · confidence \(String(format: "%.2f", candidate.confidence))",
            detail: candidate.rationale.isEmpty ? candidate.content : candidate.rationale,
            severity: candidate.kind == .riskFlag || candidate.kind == .unresolvedQuestion ? .needsReview : .info,
            sourceIDs: candidate.sourceRefIDs,
            recommendedActions: ["promote_candidate", "hold_for_review", "discard"],
            createdAt: result.createdAt
        )
    }

    private func severity(for action: GraphMemoryChangeLogAction) -> GraphMemoryProductSeverity {
        switch action {
        case .extractionCommitted:
            return .success
        case .extractionHeld, .extractionAskUser, .replayDryRun:
            return .needsReview
        case .extractionDiscarded, .manualInvalidation:
            return .warning
        case .extractionFailed:
            return .error
        }
    }
}
