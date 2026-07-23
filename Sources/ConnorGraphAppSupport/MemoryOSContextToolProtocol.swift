import Foundation
import ConnorGraphStore

public struct MemoryOSContextToolConfiguration: Sendable, Equatable {
    public var pageSize: Int
    public var maxDepth: Int
    public var maxResponseCharacters: Int

    public init(
        pageSize: Int = 40,
        maxDepth: Int = 6,
        maxResponseCharacters: Int = 30 * 1024
    ) {
        self.pageSize = max(1, pageSize)
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
    public var success: Bool
    public var reason: String
    public var query: String
    public var page: Int
    public var pageSize: Int
    public var returnedItems: Int
    public var totalItems: Int
    public var totalPages: Int
    public var hasNextPage: Bool
    public var nextPage: Int?
    public var records: [MemoryOSContextToolRecord]

    enum CodingKeys: String, CodingKey {
        case success, reason, query, page, pageSize, returnedItems, totalItems, totalPages, hasNextPage, nextPage, records
    }

    public init(success: Bool, reason: String, query: String, page: Int, pageSize: Int, returnedItems: Int, totalItems: Int, totalPages: Int, hasNextPage: Bool, nextPage: Int?, records: [MemoryOSContextToolRecord]) {
        self.success = success
        self.reason = reason
        self.query = query
        self.page = page
        self.pageSize = pageSize
        self.returnedItems = returnedItems
        self.totalItems = totalItems
        self.totalPages = totalPages
        self.hasNextPage = hasNextPage
        self.nextPage = nextPage
        self.records = records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        reason = try container.decode(String.self, forKey: .reason)
        query = try container.decode(String.self, forKey: .query)
        page = try container.decode(Int.self, forKey: .page)
        pageSize = try container.decode(Int.self, forKey: .pageSize)
        returnedItems = try container.decode(Int.self, forKey: .returnedItems)
        totalItems = try container.decode(Int.self, forKey: .totalItems)
        totalPages = try container.decode(Int.self, forKey: .totalPages)
        hasNextPage = try container.decode(Bool.self, forKey: .hasNextPage)
        nextPage = try container.decodeIfPresent(Int.self, forKey: .nextPage)
        records = try container.decodeIfPresent([MemoryOSContextToolRecord].self, forKey: .records) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(reason, forKey: .reason)
        try container.encode(query, forKey: .query)
        try container.encode(page, forKey: .page)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encode(returnedItems, forKey: .returnedItems)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(totalPages, forKey: .totalPages)
        try container.encode(hasNextPage, forKey: .hasNextPage)
        if let nextPage { try container.encode(nextPage, forKey: .nextPage) } else { try container.encodeNil(forKey: .nextPage) }
        if success { try container.encode(records, forKey: .records) } else { try container.encodeNil(forKey: .records) }
    }
}
