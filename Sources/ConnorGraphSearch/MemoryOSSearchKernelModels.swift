import Foundation

public enum MemoryOSSearchKernelLayer: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case l0 = "L0"
    case l1 = "L1"
    case l2 = "L2"
    case l3 = "L3"
    case l4 = "L4"
}

public struct MemoryOSSearchKernelRequest: Sendable, Codable, Equatable {
    public var query: String
    public var queries: [String]?
    public var layers: [MemoryOSSearchKernelLayer]
    public var limit: Int

    public init(query: String, queries: [String]? = nil, layers: [MemoryOSSearchKernelLayer] = MemoryOSSearchKernelLayer.allCases, limit: Int = 10) {
        self.query = query
        self.queries = queries
        self.layers = layers
        self.limit = limit
    }
}

public struct MemoryOSSearchKernelHit: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(layer.rawValue):\(recordID)" }
    public var layer: MemoryOSSearchKernelLayer
    public var recordID: String
    public var recordKind: String
    public var title: String
    public var snippet: String
    public var score: Double
    public var matchedChannel: String
    public var rankReason: String
    public var updatedAt: String?
    public var metadataJSON: String

    enum CodingKeys: String, CodingKey {
        case layer
        case recordID = "record_id"
        case recordKind = "record_kind"
        case title
        case snippet
        case score
        case matchedChannel = "matched_channel"
        case rankReason = "rank_reason"
        case updatedAt = "updated_at"
        case metadataJSON = "metadata_json"
    }

    public init(layer: MemoryOSSearchKernelLayer, recordID: String, recordKind: String, title: String, snippet: String, score: Double, matchedChannel: String, rankReason: String, updatedAt: String? = nil, metadataJSON: String = "{}") {
        self.layer = layer
        self.recordID = recordID
        self.recordKind = recordKind
        self.title = title
        self.snippet = snippet
        self.score = score
        self.matchedChannel = matchedChannel
        self.rankReason = rankReason
        self.updatedAt = updatedAt
        self.metadataJSON = metadataJSON
    }
}

public struct MemoryOSSearchKernelResponse: Sendable, Codable, Equatable {
    public var hits: [MemoryOSSearchKernelHit]
    public var backend: String

    public init(hits: [MemoryOSSearchKernelHit], backend: String = "tantivy-embedded") {
        self.hits = hits
        self.backend = backend
    }
}

public enum MemoryOSSearchKernelPaths {
    public static func defaultIndexDirectory(graphDirectory: URL) -> URL {
        graphDirectory
            .appendingPathComponent("search-index", isDirectory: true)
            .appendingPathComponent("memory-os-tantivy", isDirectory: true)
    }
}
