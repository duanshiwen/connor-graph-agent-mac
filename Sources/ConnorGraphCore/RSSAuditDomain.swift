import Foundation

public enum RSSAuditKind: String, Codable, Sendable, Equatable, Hashable {
    case sourceListed
    case sourceRead
    case sourceAdded
    case sourceTested
    case sourceSynced
    case itemListed
    case itemSearched
    case itemRead
    case itemContentRead
    case itemStateMutated
    case opmlImported
    case opmlExported
    case evidenceCandidateCreated
}

public enum RSSAuditRiskClass: String, Codable, Sendable, Equatable, Hashable {
    case read
    case contentRead
    case network
    case mutation
    case sourceManagement
    case importExport
}

public struct RSSAuditRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String?
    public var sessionID: String?
    public var sourceID: RSSSourceID?
    public var itemID: RSSItemID?
    public var kind: RSSAuditKind
    public var riskClass: RSSAuditRiskClass
    public var redactedSummary: String
    public var payloadHash: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, runID: String? = nil, sessionID: String? = nil, sourceID: RSSSourceID? = nil, itemID: RSSItemID? = nil, kind: RSSAuditKind, riskClass: RSSAuditRiskClass, redactedSummary: String, payloadHash: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.sourceID = sourceID
        self.itemID = itemID
        self.kind = kind
        self.riskClass = riskClass
        self.redactedSummary = redactedSummary
        self.payloadHash = payloadHash
        self.createdAt = createdAt
    }
}
