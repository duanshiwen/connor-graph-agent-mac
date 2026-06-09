import Foundation

public enum GraphWriteCandidateKind: String, Codable, Sendable, Equatable {
    case createNode
    case updateNode
    case createFact
    case updateFact
    case invalidateFact
    case attachEvidence
    case createMention
}

public enum GraphWriteCandidateStatus: String, Codable, Sendable, Equatable {
    case pendingValidation
    case validationFailed
    case pendingReview
    case approved
    case rejected
    case committed
    case superseded
}

public struct GraphWriteCandidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var groupID: String
    public var kind: GraphWriteCandidateKind
    public var proposedByRunID: String
    public var proposedByToolCallID: String?
    public var rationale: String
    public var confidence: Double
    public var payloadJSON: String
    public var sourceEpisodeIDs: [String]
    public var relatedNodeIDs: [String]
    public var relatedFactIDs: [String]
    public var status: GraphWriteCandidateStatus
    public var validationErrors: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        groupID: String,
        kind: GraphWriteCandidateKind,
        proposedByRunID: String,
        proposedByToolCallID: String? = nil,
        rationale: String,
        confidence: Double,
        payloadJSON: String,
        sourceEpisodeIDs: [String] = [],
        relatedNodeIDs: [String] = [],
        relatedFactIDs: [String] = [],
        status: GraphWriteCandidateStatus = .pendingValidation,
        validationErrors: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.kind = kind
        self.proposedByRunID = proposedByRunID
        self.proposedByToolCallID = proposedByToolCallID
        self.rationale = rationale
        self.confidence = confidence
        self.payloadJSON = payloadJSON
        self.sourceEpisodeIDs = sourceEpisodeIDs
        self.relatedNodeIDs = relatedNodeIDs
        self.relatedFactIDs = relatedFactIDs
        self.status = status
        self.validationErrors = validationErrors
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
