import Foundation
import ConnorGraphCore

public enum GraphAdmissionHoldQueueStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case investigating
    case resolved
    case dismissed
}

public enum GraphAdmissionHoldRecommendedAction: String, Codable, Sendable, CaseIterable, Equatable {
    case replayTrace = "replay_trace"
    case inspectEvidence = "inspect_evidence"
    case rerunExtraction = "rerun_extraction"
    case mergeEntity = "merge_entity"
    case groundSource = "ground_source"
    case askUserIfNeeded = "ask_user_if_needed"
}

public struct GraphAdmissionHoldQueueItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var traceID: String
    public var jobID: String
    public var graphID: String
    public var sourceID: String
    public var sourceType: GraphExtractionSourceType
    public var status: GraphAdmissionHoldQueueStatus
    public var reasons: [GraphWriteAdmissionReason]
    public var recommendedActions: [GraphAdmissionHoldRecommendedAction]
    public var message: String
    public var createdAt: Date
    public var updatedAt: Date
    public var resolvedAt: Date?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        traceID: String,
        jobID: String,
        graphID: String,
        sourceID: String,
        sourceType: GraphExtractionSourceType,
        status: GraphAdmissionHoldQueueStatus = .open,
        reasons: [GraphWriteAdmissionReason],
        recommendedActions: [GraphAdmissionHoldRecommendedAction],
        message: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        resolvedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.traceID = traceID
        self.jobID = jobID
        self.graphID = graphID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.status = status
        self.reasons = reasons
        self.recommendedActions = recommendedActions
        self.message = message
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.resolvedAt = resolvedAt
        self.metadata = metadata
    }
}

public struct GraphAdmissionHoldQueuePlanner: Sendable {
    public init() {}

    public func recommendedActions(for reasons: [GraphWriteAdmissionReason]) -> [GraphAdmissionHoldRecommendedAction] {
        var actions: [GraphAdmissionHoldRecommendedAction] = []
        func append(_ action: GraphAdmissionHoldRecommendedAction) {
            if !actions.contains(action) { actions.append(action) }
        }

        for reason in reasons {
            switch reason {
            case .lowEntityConfidence, .lowStatementConfidence:
                append(.rerunExtraction)
                append(.groundSource)
                append(.replayTrace)
            case .missingStatementEvidence:
                append(.inspectEvidence)
                append(.groundSource)
                append(.replayTrace)
            case .potentialDuplicateEntity:
                append(.mergeEntity)
                append(.replayTrace)
            case .statementConflict:
                append(.inspectEvidence)
                append(.replayTrace)
                append(.askUserIfNeeded)
            case .sensitivePersonalMemory:
                append(.askUserIfNeeded)
            case .emptyDraft:
                append(.rerunExtraction)
            case .highConfidenceEvidenceBacked:
                break
            }
        }
        return actions
    }
}
