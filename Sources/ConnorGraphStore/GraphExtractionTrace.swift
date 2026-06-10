import Foundation
import ConnorGraphCore

public enum GraphExtractionTraceOutcome: String, Codable, Sendable, Equatable {
    case committed
    case held
    case askUser = "ask_user"
    case discarded
    case failed
}

public struct GraphExtractionTrace: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var jobID: String
    public var graphID: String
    public var sourceID: String
    public var sourceType: GraphExtractionSourceType
    public var outcome: GraphExtractionTraceOutcome
    public var admissionAction: GraphWriteAdmissionDecisionAction?
    public var admissionReasons: [GraphWriteAdmissionReason]
    public var extractedEntityCount: Int
    public var extractedStatementCount: Int
    public var committedEntityCount: Int
    public var committedStatementCount: Int
    public var anomalyCount: Int
    public var errorMessage: String?
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        jobID: String,
        graphID: String,
        sourceID: String,
        sourceType: GraphExtractionSourceType,
        outcome: GraphExtractionTraceOutcome,
        admissionAction: GraphWriteAdmissionDecisionAction? = nil,
        admissionReasons: [GraphWriteAdmissionReason] = [],
        extractedEntityCount: Int = 0,
        extractedStatementCount: Int = 0,
        committedEntityCount: Int = 0,
        committedStatementCount: Int = 0,
        anomalyCount: Int = 0,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.jobID = jobID
        self.graphID = graphID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.outcome = outcome
        self.admissionAction = admissionAction
        self.admissionReasons = admissionReasons
        self.extractedEntityCount = extractedEntityCount
        self.extractedStatementCount = extractedStatementCount
        self.committedEntityCount = committedEntityCount
        self.committedStatementCount = committedStatementCount
        self.anomalyCount = anomalyCount
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.metadata = metadata
    }
}
