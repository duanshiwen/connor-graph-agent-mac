import Foundation
import ConnorGraphStore

public struct MemoryOSContextToolConfiguration: Sendable, Equatable {
    public var minimumResultLimit: Int
    public var defaultResultLimit: Int
    public var maxDepth: Int
    public var maxResponseCharacters: Int

    public init(
        minimumResultLimit: Int = 10,
        defaultResultLimit: Int = 10,
        maxDepth: Int = 6,
        maxResponseCharacters: Int = 30 * 1024
    ) {
        self.minimumResultLimit = max(1, minimumResultLimit)
        self.defaultResultLimit = max(self.minimumResultLimit, defaultResultLimit)
        self.maxDepth = max(1, maxDepth)
        self.maxResponseCharacters = max(1_024, maxResponseCharacters)
    }
}

public struct MemoryOSContextToolPathEdge: Codable, Sendable, Equatable {
    public var recordID: String
    public var sourceEntityID: String
    public var predicate: String
    public var relatedEntityID: String?
    public var text: String
    public var depth: Int

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case sourceEntityID = "source_entity_id"
        case predicate
        case relatedEntityID = "related_entity_id"
        case text
        case depth
    }
}

public struct MemoryOSContextToolRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { recordID }
    public var recordID: String
    public var layer: String
    public var text: String
    public var occurredAt: String?
    public var updatedAt: String?
    public var confidence: Double?
    public var depth: Int
    public var evidenceRefs: [String]
    public var status: String
    public var retrievalScore: Double
    public var path: [MemoryOSContextToolPathEdge]

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case layer
        case text
        case occurredAt = "occurred_at"
        case updatedAt = "updated_at"
        case confidence
        case depth
        case evidenceRefs = "evidence_refs"
        case status
        case retrievalScore = "retrieval_score"
        case path
    }
}

public struct MemoryOSContextToolResponse: Codable, Sendable, Equatable {
    public var query: String
    public var requestedLimit: Int
    public var returnedCount: Int
    public var cumulativeReturnedCount: Int
    public var hasMore: Bool?
    public var partial: Bool
    public var records: [MemoryOSContextToolRecord]

    enum CodingKeys: String, CodingKey {
        case query
        case requestedLimit
        case returnedCount
        case cumulativeReturnedCount
        case hasMore
        case partial
        case records
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(requestedLimit, forKey: .requestedLimit)
        try container.encode(returnedCount, forKey: .returnedCount)
        try container.encode(cumulativeReturnedCount, forKey: .cumulativeReturnedCount)
        if let hasMore { try container.encode(hasMore, forKey: .hasMore) } else { try container.encodeNil(forKey: .hasMore) }
        try container.encode(partial, forKey: .partial)
        try container.encode(records, forKey: .records)
    }
}

actor MemoryOSContextToolCursorStore {
    private var deliveredByKey: [String: Set<String>] = [:]

    func delivered(runID: String, queryKey: String) -> Set<String> {
        deliveredByKey["\(runID)|\(queryKey)"] ?? []
    }

    func commit(_ recordIDs: [String], runID: String, queryKey: String) -> Int {
        let key = "\(runID)|\(queryKey)"
        var delivered = deliveredByKey[key] ?? []
        delivered.formUnion(recordIDs)
        deliveredByKey[key] = delivered
        return delivered.count
    }
}
