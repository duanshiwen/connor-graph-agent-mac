import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphWriteCandidateRepository: @unchecked Sendable {
    public let store: SQLiteGraphStore
    public var committer: GraphWriteCandidateCommitService

    public init(store: SQLiteGraphStore, committer: GraphWriteCandidateCommitService = GraphWriteCandidateCommitService()) {
        self.store = store
        self.committer = committer
    }

    public func loadCandidates(status: GraphWriteCandidateStatus? = nil, limit: Int = 100) throws -> [GraphWriteCandidate] {
        try store.graphWriteCandidates(status: status, limit: limit)
    }

    @discardableResult
    public func approve(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidate {
        var updated = candidate
        updated.status = .approved
        updated.updatedAt = Date()
        try store.upsert(graphWriteCandidate: updated)
        return updated
    }

    @discardableResult
    public func reject(_ candidate: GraphWriteCandidate, reason: String? = nil) throws -> GraphWriteCandidate {
        var updated = candidate
        updated.status = .rejected
        updated.updatedAt = Date()
        if let reason, !reason.isEmpty {
            updated.validationErrors.append(reason)
        }
        try store.upsert(graphWriteCandidate: updated)
        return updated
    }

    @discardableResult
    public func commit(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidateCommitResult {
        let approved = candidate.status == .approved ? candidate : try approve(candidate)
        let result = try committer.commit(approved, store: store)
        var updated = approved
        updated.status = .committed
        updated.updatedAt = Date()
        try store.upsert(graphWriteCandidate: updated)
        return result
    }
}

public struct GraphWriteCandidateCommitResult: Sendable, Equatable {
    public var candidateID: String
    public var createdNodeIDs: [String]
    public var createdFactIDs: [String]
    public var updatedFactIDs: [String]
    public var attachedEvidenceFactIDs: [String]

    public init(candidateID: String, createdNodeIDs: [String] = [], createdFactIDs: [String] = [], updatedFactIDs: [String] = [], attachedEvidenceFactIDs: [String] = []) {
        self.candidateID = candidateID
        self.createdNodeIDs = createdNodeIDs
        self.createdFactIDs = createdFactIDs
        self.updatedFactIDs = updatedFactIDs
        self.attachedEvidenceFactIDs = attachedEvidenceFactIDs
    }
}

public struct GraphWriteCandidateCommitService: Sendable {
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func commit(_ candidate: GraphWriteCandidate, store: SQLiteGraphStore) throws -> GraphWriteCandidateCommitResult {
        guard candidate.status == .approved else {
            throw GraphWriteCandidateCommitError.notApproved(candidate.id)
        }
        switch candidate.kind {
        case .createNode:
            let payload = try decoder.decode(CreateNodePayload.self, from: Data(candidate.payloadJSON.utf8))
            let node = GraphNodeV2(
                id: payload.id ?? UUID().uuidString,
                groupID: candidate.groupID,
                stableKey: payload.stableKey,
                type: payload.nodeType,
                canonicalName: payload.canonicalName,
                title: payload.title,
                summary: payload.summary,
                labels: payload.labels,
                attributes: payload.attributes,
                confidence: payload.confidence ?? candidate.confidence,
                metadata: payload.metadata.merging(["committedFromCandidateID": candidate.id]) { current, _ in current }
            )
            try store.upsert(nodeV2: node)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, createdNodeIDs: [node.id])

        case .createFact:
            let payload = try decoder.decode(CreateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
            guard try store.graphNodeV2(id: payload.sourceNodeID) != nil else { throw GraphWriteCandidateCommitError.missingNode(payload.sourceNodeID) }
            guard try store.graphNodeV2(id: payload.targetNodeID) != nil else { throw GraphWriteCandidateCommitError.missingNode(payload.targetNodeID) }
            let fact = GraphFact(
                id: payload.id ?? UUID().uuidString,
                groupID: candidate.groupID,
                sourceNodeID: payload.sourceNodeID,
                targetNodeID: payload.targetNodeID,
                relation: payload.relation,
                fact: payload.fact,
                confidence: payload.confidence ?? candidate.confidence,
                validAt: payload.validAt,
                referenceTime: payload.referenceTime,
                attributes: payload.attributes,
                metadata: payload.metadata.merging(["committedFromCandidateID": candidate.id]) { current, _ in current }
            )
            try store.upsert(fact: fact, sourceEpisodeIDs: candidate.sourceEpisodeIDs + payload.sourceEpisodeIDs)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, createdFactIDs: [fact.id])

        case .invalidateFact:
            let payload = try decoder.decode(InvalidateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
            guard var fact = try store.graphFact(id: payload.factID) else { throw GraphWriteCandidateCommitError.missingFact(payload.factID) }
            fact.status = .invalidated
            fact.invalidAt = payload.invalidAt ?? Date()
            fact.invalidatedByFactID = payload.invalidatedByFactID
            fact.updatedAt = Date()
            fact.metadata["invalidatedFromCandidateID"] = candidate.id
            if let reason = payload.reason { fact.metadata["invalidationReason"] = reason }
            try store.upsert(fact: fact)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, updatedFactIDs: [fact.id])

        case .attachEvidence:
            let payload = try decoder.decode(AttachEvidencePayload.self, from: Data(candidate.payloadJSON.utf8))
            guard let fact = try store.graphFact(id: payload.factID) else { throw GraphWriteCandidateCommitError.missingFact(payload.factID) }
            try store.upsert(fact: fact, sourceEpisodeIDs: candidate.sourceEpisodeIDs + payload.episodeIDs)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, attachedEvidenceFactIDs: [fact.id])

        case .updateNode, .updateFact, .createMention:
            throw GraphWriteCandidateCommitError.unsupportedCandidateKind(candidate.kind)
        }
    }
}

public enum GraphWriteCandidateCommitError: Error, Sendable, Equatable, CustomStringConvertible {
    case notApproved(String)
    case unsupportedCandidateKind(GraphWriteCandidateKind)
    case missingNode(String)
    case missingFact(String)

    public var description: String {
        switch self {
        case .notApproved(let id): return "Candidate must be approved before commit: \(id)"
        case .unsupportedCandidateKind(let kind): return "Unsupported candidate kind for commit: \(kind.rawValue)"
        case .missingNode(let id): return "Missing graph node: \(id)"
        case .missingFact(let id): return "Missing graph fact: \(id)"
        }
    }
}

private struct CreateNodePayload: Decodable {
    var id: String?
    var stableKey: String?
    var nodeType: NodeType
    var canonicalName: String
    var title: String
    var summary: String
    var labels: [String]
    var attributes: [String: String]
    var confidence: Double?
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, stableKey, nodeType, canonicalName, title, summary, labels, attributes, confidence, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        stableKey = try c.decodeIfPresent(String.self, forKey: .stableKey)
        nodeType = try c.decode(NodeType.self, forKey: .nodeType)
        canonicalName = try c.decode(String.self, forKey: .canonicalName)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        attributes = try c.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

private struct CreateFactPayload: Decodable {
    var id: String?
    var sourceNodeID: String
    var targetNodeID: String
    var relation: RelationType
    var fact: String
    var confidence: Double?
    var validAt: Date?
    var referenceTime: Date?
    var sourceEpisodeIDs: [String]
    var attributes: [String: String]
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, sourceNodeID, targetNodeID, relation, fact, confidence, validAt, referenceTime, sourceEpisodeIDs, attributes, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        sourceNodeID = try c.decode(String.self, forKey: .sourceNodeID)
        targetNodeID = try c.decode(String.self, forKey: .targetNodeID)
        relation = try c.decode(RelationType.self, forKey: .relation)
        fact = try c.decode(String.self, forKey: .fact)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        validAt = try c.decodeIfPresent(Date.self, forKey: .validAt)
        referenceTime = try c.decodeIfPresent(Date.self, forKey: .referenceTime)
        sourceEpisodeIDs = try c.decodeIfPresent([String].self, forKey: .sourceEpisodeIDs) ?? []
        attributes = try c.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

private struct InvalidateFactPayload: Decodable {
    var factID: String
    var reason: String?
    var invalidAt: Date?
    var invalidatedByFactID: String?
}

private struct AttachEvidencePayload: Decodable {
    var factID: String
    var episodeIDs: [String]
}
