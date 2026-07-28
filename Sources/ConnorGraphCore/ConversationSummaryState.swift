import Foundation

public enum ConversationSummaryItemStatus: String, Codable, Sendable, Equatable {
    case active
    case resolved
    case superseded
}

public struct ConversationSummaryItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var status: ConversationSummaryItemStatus
    public var text: String
    public var sourceMessageIDs: [String]

    public init(
        id: String,
        status: ConversationSummaryItemStatus = .active,
        text: String,
        sourceMessageIDs: [String] = []
    ) {
        self.id = id
        self.status = status
        self.text = text
        self.sourceMessageIDs = sourceMessageIDs
    }
}

public struct ConversationSummaryAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var kind: AgentAttachmentKind
    public var description: String

    public init(id: String, displayName: String, kind: AgentAttachmentKind, description: String) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.description = description
    }
}

public struct ConversationSummaryPayload: Codable, Sendable, Equatable {
    public var currentGoal: String
    public var userConstraints: [ConversationSummaryItem]
    public var decisions: [ConversationSummaryItem]
    public var completedWork: [ConversationSummaryItem]
    public var importantFacts: [ConversationSummaryItem]
    public var filesAndArtifacts: [ConversationSummaryItem]
    public var pendingWork: [ConversationSummaryItem]
    public var attachments: [ConversationSummaryAttachment]

    public init(
        currentGoal: String = "",
        userConstraints: [ConversationSummaryItem] = [],
        decisions: [ConversationSummaryItem] = [],
        completedWork: [ConversationSummaryItem] = [],
        importantFacts: [ConversationSummaryItem] = [],
        filesAndArtifacts: [ConversationSummaryItem] = [],
        pendingWork: [ConversationSummaryItem] = [],
        attachments: [ConversationSummaryAttachment] = []
    ) {
        self.currentGoal = currentGoal
        self.userConstraints = userConstraints
        self.decisions = decisions
        self.completedWork = completedWork
        self.importantFacts = importantFacts
        self.filesAndArtifacts = filesAndArtifacts
        self.pendingWork = pendingWork
        self.attachments = attachments
    }

    public var allItems: [ConversationSummaryItem] {
        userConstraints + decisions + completedWork + importantFacts + filesAndArtifacts + pendingWork
    }
}

public enum ConversationSummaryStateStatus: String, Codable, Sendable, Equatable {
    case active
    case stale
    case failed
}

public struct ConversationSummaryState: Codable, Sendable, Equatable {
    public var sessionID: String
    public var revision: Int
    public var compressionGeneration: Int
    public var payload: ConversationSummaryPayload
    public var coveredThroughMessageID: String
    public var coveredMessageCount: Int
    public var coveredPrefixHash: String
    public var previousSummaryHash: String?
    public var currentSummaryHash: String
    public var sourceTokenEstimate: Int
    public var summaryTokenEstimate: Int
    public var generationModelID: String
    public var status: ConversationSummaryStateStatus
    public var generatedAt: Date

    public init(
        sessionID: String,
        revision: Int,
        compressionGeneration: Int,
        payload: ConversationSummaryPayload,
        coveredThroughMessageID: String,
        coveredMessageCount: Int,
        coveredPrefixHash: String,
        previousSummaryHash: String? = nil,
        currentSummaryHash: String,
        sourceTokenEstimate: Int,
        summaryTokenEstimate: Int,
        generationModelID: String,
        status: ConversationSummaryStateStatus = .active,
        generatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.revision = revision
        self.compressionGeneration = compressionGeneration
        self.payload = payload
        self.coveredThroughMessageID = coveredThroughMessageID
        self.coveredMessageCount = coveredMessageCount
        self.coveredPrefixHash = coveredPrefixHash
        self.previousSummaryHash = previousSummaryHash
        self.currentSummaryHash = currentSummaryHash
        self.sourceTokenEstimate = sourceTokenEstimate
        self.summaryTokenEstimate = summaryTokenEstimate
        self.generationModelID = generationModelID
        self.status = status
        self.generatedAt = generatedAt
    }
}

public enum ConversationCompactionRecordStatus: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case interrupted
}

public struct ConversationCompactionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var generation: Int
    public var baseRevision: Int
    public var previousCutoffMessageID: String?
    public var newCutoffMessageID: String
    public var deltaMessageIDs: [String]
    public var deltaAttachmentIDs: [String]
    public var previousSummaryHash: String?
    public var newSummaryHash: String
    public var modelID: String
    public var startedAt: Date
    public var completedAt: Date
    public var status: ConversationCompactionRecordStatus
    public var failureReason: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        generation: Int,
        baseRevision: Int,
        previousCutoffMessageID: String? = nil,
        newCutoffMessageID: String,
        deltaMessageIDs: [String],
        deltaAttachmentIDs: [String],
        previousSummaryHash: String? = nil,
        newSummaryHash: String,
        modelID: String,
        startedAt: Date,
        completedAt: Date,
        status: ConversationCompactionRecordStatus,
        failureReason: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.generation = generation
        self.baseRevision = baseRevision
        self.previousCutoffMessageID = previousCutoffMessageID
        self.newCutoffMessageID = newCutoffMessageID
        self.deltaMessageIDs = deltaMessageIDs
        self.deltaAttachmentIDs = deltaAttachmentIDs
        self.previousSummaryHash = previousSummaryHash
        self.newSummaryHash = newSummaryHash
        self.modelID = modelID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.failureReason = failureReason
    }
}
