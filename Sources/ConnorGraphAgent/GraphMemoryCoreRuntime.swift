import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch

public enum AgentGraphMemoryUsePolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case disabled
    case passiveContext = "passive_context"
    case activeContext = "active_context"
    case activeContextAndFeedback = "active_context_and_feedback"
}

public enum AgentGraphMemoryContextItemRole: String, Codable, Sendable, Equatable, CaseIterable {
    case background
    case preference
    case decision
    case projectState = "project_state"
    case profile
    case risk
    case openQuestion = "open_question"
    case evidence
}

public struct AgentGraphMemoryContextItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sourceID }
    public var sourceID: String
    public var kind: GraphSearchResultKind
    public var role: AgentGraphMemoryContextItemRole
    public var content: String
    public var reason: String
    public var scoreLabel: String
    public var evidenceEpisodeIDs: [String]
    public var metadata: [String: String]

    public init(
        sourceID: String,
        kind: GraphSearchResultKind,
        role: AgentGraphMemoryContextItemRole = .background,
        content: String,
        reason: String,
        scoreLabel: String = "",
        evidenceEpisodeIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.sourceID = sourceID
        self.kind = kind
        self.role = role
        self.content = content
        self.reason = reason
        self.scoreLabel = scoreLabel
        self.evidenceEpisodeIDs = evidenceEpisodeIDs
        self.metadata = metadata
    }
}

public struct AgentGraphMemoryRetrievalMetrics: Codable, Sendable, Equatable {
    public var itemCount: Int
    public var evidenceEpisodeCount: Int
    public var roleCounts: [String: Int]
    public var retrievalMethods: [String]

    public init(
        itemCount: Int = 0,
        evidenceEpisodeCount: Int = 0,
        roleCounts: [String: Int] = [:],
        retrievalMethods: [String] = []
    ) {
        self.itemCount = itemCount
        self.evidenceEpisodeCount = evidenceEpisodeCount
        self.roleCounts = roleCounts
        self.retrievalMethods = retrievalMethods
    }
}

public struct AgentGraphMemoryContextContract: Codable, Sendable, Equatable {
    public var query: String
    public var sessionID: String?
    public var runID: String?
    public var groupID: String
    public var generatedAt: Date
    public var policy: AgentGraphMemoryUsePolicy
    public var items: [AgentGraphMemoryContextItem]
    public var summary: String
    public var hasStaleSignals: Bool
    public var hasConflictSignals: Bool
    public var hasUncertaintySignals: Bool
    public var retrievalMetrics: AgentGraphMemoryRetrievalMetrics

    public init(
        query: String,
        sessionID: String? = nil,
        runID: String? = nil,
        groupID: String,
        generatedAt: Date = Date(),
        policy: AgentGraphMemoryUsePolicy = .activeContext,
        items: [AgentGraphMemoryContextItem] = [],
        summary: String = "",
        hasStaleSignals: Bool = false,
        hasConflictSignals: Bool = false,
        hasUncertaintySignals: Bool = false,
        retrievalMetrics: AgentGraphMemoryRetrievalMetrics = AgentGraphMemoryRetrievalMetrics()
    ) {
        self.query = query
        self.sessionID = sessionID
        self.runID = runID
        self.groupID = groupID
        self.generatedAt = generatedAt
        self.policy = policy
        self.items = items
        self.summary = summary
        self.hasStaleSignals = hasStaleSignals
        self.hasConflictSignals = hasConflictSignals
        self.hasUncertaintySignals = hasUncertaintySignals
        self.retrievalMetrics = retrievalMetrics
    }

    public var agentContext: AgentContext {
        AgentContext(query: query, items: items.map { item in
            AgentContextItem(
                sourceID: item.sourceID,
                kind: item.kind,
                content: item.content,
                reason: "\(item.reason); memory role \(item.role.rawValue)"
            )
        })
    }

    public var renderedText: String { agentContext.renderedText }
}

public enum AgentGraphMemoryFeedbackTrigger: String, Codable, Sendable, Equatable, CaseIterable {
    case userMessage = "user_message"
    case assistantMessage = "assistant_message"
    case sessionClosed = "session_closed"
    case explicitRemember = "explicit_remember"
    case highValueSignal = "high_value_signal"
    case tokenBudget = "token_budget"
    case idle = "idle"
    case batchSize = "batch_size"
}

public struct AgentGraphMemoryFeedbackSignal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String?
    public var sessionID: String
    public var trigger: AgentGraphMemoryFeedbackTrigger
    public var candidateKind: String
    public var importance: Double
    public var confidence: Double
    public var rationale: String
    public var explicitRemember: Bool
    public var highValue: Bool
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        runID: String? = nil,
        sessionID: String,
        trigger: AgentGraphMemoryFeedbackTrigger,
        candidateKind: String = "episode",
        importance: Double = 0.5,
        confidence: Double = 0.5,
        rationale: String = "",
        explicitRemember: Bool = false,
        highValue: Bool = false,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.trigger = trigger
        self.candidateKind = candidateKind
        self.importance = importance
        self.confidence = confidence
        self.rationale = rationale
        self.explicitRemember = explicitRemember
        self.highValue = highValue
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public extension AgentGraphMemoryFeedbackSignal {
    static func signals(
        from result: MemoryIngestionResult,
        runID: String? = nil,
        sessionID: String,
        createdAt: Date = Date()
    ) -> [AgentGraphMemoryFeedbackSignal] {
        result.triggerReasons.map { reason in
            AgentGraphMemoryFeedbackSignal(
                runID: runID,
                sessionID: sessionID,
                trigger: AgentGraphMemoryFeedbackTrigger(reason),
                candidateKind: "episode",
                importance: importance(for: reason),
                confidence: 0.75,
                rationale: "Memory staging triggered by \(reason.rawValue); \(result.buffer.pendingBundles.count) pending bundle(s) are available for distillation.",
                explicitRemember: reason == .explicitRememberRequest,
                highValue: reason == .highValueSignal,
                createdAt: createdAt,
                metadata: [
                    "source_buffer_id": result.buffer.id,
                    "pending_bundle_count": "\(result.buffer.pendingBundles.count)",
                    "appended_bundle_ids": result.appendedBundleIDs.joined(separator: ","),
                    "updated_bundle_ids": result.updatedBundleIDs.joined(separator: ",")
                ]
            )
        }
    }

    private static func importance(for reason: MemoryStagingTriggerReason) -> Double {
        switch reason {
        case .explicitRememberRequest: 0.95
        case .highValueSignal: 0.9
        case .sessionClosed: 0.8
        case .tokenBudgetExceeded: 0.75
        case .bundleCountReached: 0.7
        case .sessionIdle: 0.6
        }
    }
}

public extension AgentGraphMemoryFeedbackTrigger {
    init(_ reason: MemoryStagingTriggerReason) {
        switch reason {
        case .bundleCountReached: self = .batchSize
        case .sessionIdle: self = .idle
        case .sessionClosed: self = .sessionClosed
        case .explicitRememberRequest: self = .explicitRemember
        case .highValueSignal: self = .highValueSignal
        case .tokenBudgetExceeded: self = .tokenBudget
        }
    }
}

public struct AgentGraphMemoryRuntimeSnapshot: Codable, Sendable, Equatable {
    public var contextContract: AgentGraphMemoryContextContract?
    public var feedbackSignals: [AgentGraphMemoryFeedbackSignal]
    public var stagedBundleCount: Int
    public var distillationCandidateCount: Int
    public var pendingCandidateCount: Int
    public var openHoldCount: Int
    public var recentChangeCount: Int

    public init(
        contextContract: AgentGraphMemoryContextContract? = nil,
        feedbackSignals: [AgentGraphMemoryFeedbackSignal] = [],
        stagedBundleCount: Int = 0,
        distillationCandidateCount: Int = 0,
        pendingCandidateCount: Int = 0,
        openHoldCount: Int = 0,
        recentChangeCount: Int = 0
    ) {
        self.contextContract = contextContract
        self.feedbackSignals = feedbackSignals
        self.stagedBundleCount = stagedBundleCount
        self.distillationCandidateCount = distillationCandidateCount
        self.pendingCandidateCount = pendingCandidateCount
        self.openHoldCount = openHoldCount
        self.recentChangeCount = recentChangeCount
    }
}
