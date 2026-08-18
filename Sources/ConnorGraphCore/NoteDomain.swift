import Foundation

public enum NoteOriginKind: String, Codable, Sendable, Equatable {
    case native
    case imported
}

/** 笔记正文的内容格式：Markdown（默认）或 HTML（多态渲染/编辑分派依据）。 */
public enum NoteContentFormat: String, Codable, Sendable, Equatable {
    case markdown
    case html
}

public enum NoteProjectionStatus: String, Codable, Sendable, Equatable {
    case pending
    case projecting
    case projected
    case indexed
    case failed
    case cleanupRequired = "cleanup_required"
}

public struct NoteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var sourceMessageID: String
    public var title: String
    public var body: String
    /** 正文格式；默认 Markdown，Notion HTML 导出等导入为 HTML。 */
    public var format: NoteContentFormat
    public var contentHash: String
    public var sourceUpdatedAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var indexVersion: Int
    public var projectionStatus: NoteProjectionStatus
    public var indexedAt: Date?
    public var failureCount: Int
    public var nextRetryAt: Date?
    public var lastErrorCode: String?
    public var originKind: NoteOriginKind
    public var importItemID: String?
    public var importSourceID: String?
    public var sourceKind: String?
    public var sourceIdentity: String?
    public var externalID: String?
    public var relativePath: String?
    public var sourceCreatedAt: Date?
    public var leaseOwner: String?
    public var leaseExpiresAt: Date?
    /** 导入来源的树形层级（如 Notion「笔记本/子分类/子页面」），空表示未保留层级。 */
    public var importHierarchy: [String]
    /** 树形层级重建后的上级笔记 sourceIdentity（根节点为 nil）。 */
    public var importParentIdentity: String?

    public init(
        id: String,
        sessionID: String,
        sourceMessageID: String,
        title: String,
        body: String,
        format: NoteContentFormat = .markdown,
        contentHash: String,
        sourceUpdatedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        indexVersion: Int = 0,
        projectionStatus: NoteProjectionStatus = .pending,
        indexedAt: Date? = nil,
        failureCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastErrorCode: String? = nil,
        originKind: NoteOriginKind = .native,
        importItemID: String? = nil,
        importSourceID: String? = nil,
        sourceKind: String? = nil,
        sourceIdentity: String? = nil,
        externalID: String? = nil,
        relativePath: String? = nil,
        sourceCreatedAt: Date? = nil,
        leaseOwner: String? = nil,
        leaseExpiresAt: Date? = nil,
        importHierarchy: [String] = [],
        importParentIdentity: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.body = body
        self.format = format
        self.contentHash = contentHash
        self.sourceUpdatedAt = sourceUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.indexVersion = indexVersion
        self.projectionStatus = projectionStatus
        self.indexedAt = indexedAt
        self.failureCount = failureCount
        self.nextRetryAt = nextRetryAt
        self.lastErrorCode = lastErrorCode
        self.originKind = originKind
        self.importItemID = importItemID
        self.importSourceID = importSourceID
        self.sourceKind = sourceKind
        self.sourceIdentity = sourceIdentity
        self.externalID = externalID
        self.relativePath = relativePath
        self.sourceCreatedAt = sourceCreatedAt
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.importHierarchy = importHierarchy
        self.importParentIdentity = importParentIdentity
    }
}

public struct NoteProjectionCandidate: Sendable, Equatable {
    public var sessionID: String
    public var title: String
    public var sourceMessageID: String
    public var messageJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(sessionID: String, title: String, sourceMessageID: String, messageJSON: String, createdAt: Date, updatedAt: Date) {
        self.sessionID = sessionID
        self.title = title
        self.sourceMessageID = sourceMessageID
        self.messageJSON = messageJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NoteImportProjectionMetadata: Sendable, Equatable {
    public var itemID: String
    public var sourceID: String
    public var sourceKind: String
    public var sourceIdentity: String
    public var externalID: String?
    public var relativePath: String?
    public var sourceCreatedAt: Date?
    /** 导入笔记的正文格式（Notion HTML 导出为 .html，其余默认 Markdown）。 */
    public var contentFormat: NoteContentFormat
    /** 导入来源的树形层级（如 Notion「笔记本/子分类/子页面」）。 */
    public var hierarchy: [String]
    /** 树形层级重建后的上级笔记 sourceIdentity（根节点为 nil）。 */
    public var parentSourceIdentity: String?

    public init(itemID: String, sourceID: String, sourceKind: String, sourceIdentity: String, externalID: String? = nil, relativePath: String? = nil, sourceCreatedAt: Date? = nil, contentFormat: NoteContentFormat = .markdown, hierarchy: [String] = [], parentSourceIdentity: String? = nil) {
        self.itemID = itemID
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.sourceIdentity = sourceIdentity
        self.externalID = externalID
        self.relativePath = relativePath
        self.sourceCreatedAt = sourceCreatedAt
        self.contentFormat = contentFormat
        self.hierarchy = hierarchy
        self.parentSourceIdentity = parentSourceIdentity
    }
}

public enum NoteSearchHealthStatus: String, Codable, Sendable, Equatable {
    case uninitialized
    case backfilling
    case available
    case partialFailure = "partial_failure"
    case repairRequired = "repair_required"
}

public struct NoteSearchHit: Codable, Sendable, Equatable {
    public var noteID: String
    public var sessionID: String
    public var title: String
    public var snippet: String
    public var matchedTerms: [String]
    public var relevance: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var originKind: NoteOriginKind
    public var sourceKind: String?
    public var projectionStatus: NoteProjectionStatus

    public init(noteID: String, sessionID: String, title: String, snippet: String, matchedTerms: [String], relevance: Double, createdAt: Date, updatedAt: Date, originKind: NoteOriginKind, sourceKind: String?, projectionStatus: NoteProjectionStatus) {
        self.noteID = noteID
        self.sessionID = sessionID
        self.title = title
        self.snippet = snippet
        self.matchedTerms = matchedTerms
        self.relevance = relevance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originKind = originKind
        self.sourceKind = sourceKind
        self.projectionStatus = projectionStatus
    }
}

public struct NoteSearchPage: Codable, Sendable, Equatable {
    public var records: [NoteSearchHit]
    public var totalItems: Int
    public var health: NoteSearchHealthStatus

    public init(records: [NoteSearchHit], totalItems: Int, health: NoteSearchHealthStatus) {
        self.records = records
        self.totalItems = totalItems
        self.health = health
    }
}
