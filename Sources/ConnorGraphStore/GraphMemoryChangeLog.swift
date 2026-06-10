import Foundation
import ConnorGraphCore

public enum GraphMemoryChangeLogAction: String, Codable, Sendable, CaseIterable, Equatable {
    case extractionCommitted = "extraction_committed"
    case extractionHeld = "extraction_held"
    case extractionAskUser = "extraction_ask_user"
    case extractionDiscarded = "extraction_discarded"
    case extractionFailed = "extraction_failed"
    case replayDryRun = "replay_dry_run"
    case manualInvalidation = "manual_invalidation"
}

public struct GraphMemoryChangeLogEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var graphID: String
    public var action: GraphMemoryChangeLogAction
    public var traceID: String?
    public var jobID: String?
    public var sourceID: String?
    public var sourceType: GraphExtractionSourceType?
    public var entityIDs: [String]
    public var statementIDs: [String]
    public var anomalyIDs: [String]
    public var summary: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        graphID: String,
        action: GraphMemoryChangeLogAction,
        traceID: String? = nil,
        jobID: String? = nil,
        sourceID: String? = nil,
        sourceType: GraphExtractionSourceType? = nil,
        entityIDs: [String] = [],
        statementIDs: [String] = [],
        anomalyIDs: [String] = [],
        summary: String,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.action = action
        self.traceID = traceID
        self.jobID = jobID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.entityIDs = entityIDs
        self.statementIDs = statementIDs
        self.anomalyIDs = anomalyIDs
        self.summary = summary
        self.createdAt = createdAt
        self.metadata = metadata
    }
}
