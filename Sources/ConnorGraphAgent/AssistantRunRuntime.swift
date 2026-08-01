import Foundation
import ConnorGraphCore

public enum AssistantRunStage: String, Codable, Sendable, Equatable, CaseIterable {
    case bootstrap
    case decide
    case execute
    case waitingForApproval
    case finalAttention
    case finalize
    case completed
}

public struct AssistantRunEnvelope: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var groupID: String
    public var userMessage: String
    public var permissionMode: AgentPermissionMode
    public var startedAt: Date
    public var timeZoneIdentifier: String

    public init(request: AgentChatRequest, now: Date = Date(), timeZone: TimeZone = .current) {
        runID = request.runID
        sessionID = request.sessionID
        groupID = request.groupID
        userMessage = request.userMessage
        permissionMode = request.permissionMode
        startedAt = now
        timeZoneIdentifier = timeZone.identifier
    }
}

public struct AssistantRunBudget: Codable, Sendable, Equatable {
    public var maximumModelTurns: Int
    public var maximumToolCalls: Int
    public var maximumContextPackTokens: Int
    public var maximumVisibleToolResultTokens: Int

    public init(
        maximumModelTurns: Int = 8,
        maximumToolCalls: Int = 24,
        maximumContextPackTokens: Int = 4_000,
        maximumVisibleToolResultTokens: Int = 2_000
    ) {
        self.maximumModelTurns = max(1, maximumModelTurns)
        self.maximumToolCalls = max(1, maximumToolCalls)
        self.maximumContextPackTokens = max(256, maximumContextPackTokens)
        self.maximumVisibleToolResultTokens = max(128, maximumVisibleToolResultTokens)
    }
}

public struct AssistantEvidenceItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var source: String
    public var summary: String
    public var citation: String?
    public var occurredAt: Date?
    public var relevance: Double?

    public init(
        id: String,
        source: String,
        summary: String,
        citation: String? = nil,
        occurredAt: Date? = nil,
        relevance: Double? = nil
    ) {
        self.id = id
        self.source = source
        self.summary = summary
        self.citation = citation
        self.occurredAt = occurredAt
        self.relevance = relevance
    }
}

public struct AssistantContextPack: Codable, Sendable, Equatable {
    public var recentMemory: [AssistantEvidenceItem]
    public var durableKnowledge: [AssistantEvidenceItem]
    public var userProfile: [AssistantEvidenceItem]
    public var noteCandidates: [AssistantEvidenceItem]
    public var failures: [String]

    public init(
        recentMemory: [AssistantEvidenceItem] = [],
        durableKnowledge: [AssistantEvidenceItem] = [],
        userProfile: [AssistantEvidenceItem] = [],
        noteCandidates: [AssistantEvidenceItem] = [],
        failures: [String] = []
    ) {
        self.recentMemory = recentMemory
        self.durableKnowledge = durableKnowledge
        self.userProfile = userProfile
        self.noteCandidates = noteCandidates
        self.failures = failures
    }

    public var isEmpty: Bool {
        recentMemory.isEmpty && durableKnowledge.isEmpty && userProfile.isEmpty && noteCandidates.isEmpty
    }
}

public struct AssistantRunState: Codable, Sendable, Equatable {
    public var envelope: AssistantRunEnvelope
    public var stage: AssistantRunStage
    public var modelTurns: Int
    public var toolCalls: Int
    public var contextPack: AssistantContextPack?

    public init(envelope: AssistantRunEnvelope) {
        self.envelope = envelope
        stage = .bootstrap
        modelTurns = 0
        toolCalls = 0
        contextPack = nil
    }

    public mutating func transition(to next: AssistantRunStage) {
        stage = next
    }
}
