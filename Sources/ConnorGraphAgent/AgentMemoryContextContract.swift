import Foundation
import ConnorGraphCore
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

    public init(sourceID: String, kind: GraphSearchResultKind, role: AgentGraphMemoryContextItemRole = .background, content: String, reason: String, scoreLabel: String = "", evidenceEpisodeIDs: [String] = [], metadata: [String: String] = [:]) {
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

    public init(itemCount: Int = 0, evidenceEpisodeCount: Int = 0, roleCounts: [String: Int] = [:], retrievalMethods: [String] = []) {
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

    public init(query: String, sessionID: String? = nil, runID: String? = nil, groupID: String, generatedAt: Date = Date(), policy: AgentGraphMemoryUsePolicy = .activeContext, items: [AgentGraphMemoryContextItem] = [], summary: String = "", hasStaleSignals: Bool = false, hasConflictSignals: Bool = false, hasUncertaintySignals: Bool = false, retrievalMetrics: AgentGraphMemoryRetrievalMetrics = AgentGraphMemoryRetrievalMetrics()) {
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
            AgentContextItem(sourceID: item.sourceID, kind: item.kind, content: item.content, reason: "\(item.reason); memory role \(item.role.rawValue)")
        })
    }

    public var renderedText: String { agentContext.renderedText }
}
