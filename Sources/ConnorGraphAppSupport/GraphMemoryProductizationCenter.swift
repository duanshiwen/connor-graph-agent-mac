import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

public enum GraphMemoryProductCardKind: String, Codable, Sendable, Equatable {
    case writeCandidate
    case admissionHold
    case changeLog
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

    public init(pendingCandidateCount: Int, openHoldCount: Int, recentChangeCount: Int) {
        self.pendingCandidateCount = pendingCandidateCount
        self.openHoldCount = openHoldCount
        self.recentChangeCount = recentChangeCount
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

public struct GraphMemoryDashboard: Sendable, Equatable {
    public var summary: GraphMemoryDashboardSummary
    public var cards: [GraphMemoryProductCard]

    public init(summary: GraphMemoryDashboardSummary, cards: [GraphMemoryProductCard]) {
        self.summary = summary
        self.cards = cards
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
                recentChangeCount: changes.count
            ),
            cards: Array(cards.prefix(limit))
        )
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
