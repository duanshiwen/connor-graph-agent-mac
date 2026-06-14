import Foundation

public enum AgentRunStatus: String, Codable, Sendable, Equatable {
    case queued
    case pending
    case running
    case waitingForApproval = "waiting_for_approval"
    case completed
    case failed
    case cancelled
}

public struct AgentRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var groupID: String
    public var status: AgentRunStatus
    public var startedAt: Date
    public var completedAt: Date?
    public var model: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        groupID: String,
        status: AgentRunStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        model: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.groupID = groupID
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.model = model
        self.metadata = metadata
    }
}

public enum AgentEventKind: String, Codable, Sendable, Equatable {
    case runStarted
    case turnStarted
    case turnCompleted
    case textDelta
    case textComplete
    case assistantMessageCreated
    case toolRequested
    case toolApproved
    case toolStarted
    case toolFinished
    case toolFailed
    case permissionRequested
    case permissionResolved
    case budgetWarning
    case sessionStatusChanged
    case sessionLabelsChanged
    case sessionArchived
    case sessionRestored
    case artifactCreated
    case sourceRegistryChanged
    case skillRegistryChanged
    case automationTriggered
    case graphMemoryProposed
    case graphMemoryCommitted
    case graphMemoryHeld
    case runFailed
    case runCompleted
}

public struct PersistedAgentEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var sessionID: String
    public var kind: AgentEventKind
    public var payloadJSON: String
    public var sequence: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        runID: String,
        sessionID: String,
        kind: AgentEventKind,
        payloadJSON: String,
        sequence: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.sequence = sequence
        self.createdAt = createdAt
    }
}

public struct AgentRunStartedEvent: Codable, Sendable, Equatable {
    public var run: AgentRun

    public init(run: AgentRun) {
        self.run = run
    }
}

public struct AgentTurnStartedEvent: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var turnIndex: Int

    public init(runID: String, sessionID: String, turnIndex: Int) {
        self.runID = runID
        self.sessionID = sessionID
        self.turnIndex = turnIndex
    }
}

public struct AgentTurnCompletedEvent: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var turnIndex: Int
    public var assistantText: String?
    public var toolCallCount: Int
    public var toolResultCount: Int
    public var stoppedAfterTurn: Bool

    public init(
        runID: String,
        sessionID: String,
        turnIndex: Int,
        assistantText: String? = nil,
        toolCallCount: Int = 0,
        toolResultCount: Int = 0,
        stoppedAfterTurn: Bool = false
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.assistantText = assistantText
        self.toolCallCount = toolCallCount
        self.toolResultCount = toolResultCount
        self.stoppedAfterTurn = stoppedAfterTurn
    }
}

public struct AgentTextDeltaEvent: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var text: String

    public init(runID: String, sessionID: String, text: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.text = text
    }
}

public struct AgentTextCompleteEvent: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var text: String
    public var citations: [String]
    public var contextSnapshot: String?

    public init(
        runID: String,
        sessionID: String,
        text: String,
        citations: [String] = [],
        contextSnapshot: String? = nil
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.text = text
        self.citations = citations
        self.contextSnapshot = contextSnapshot
    }
}

public struct AgentRunCompletedEvent: Codable, Sendable, Equatable {
    public var run: AgentRun

    public init(run: AgentRun) {
        self.run = run
    }
}

public struct AgentRunFailure: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var message: String

    public init(runID: String, sessionID: String, message: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.message = message
    }
}

public struct AgentBudgetWarning: Codable, Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var message: String

    public init(runID: String, sessionID: String, message: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.message = message
    }
}

public struct AgentSessionGovernanceEvent: Codable, Sendable, Equatable {
    public var runID: String?
    public var sessionID: String
    public var message: String
    public var status: AgentSessionStatus?
    public var labels: [AgentSessionLabel]

    public init(runID: String? = nil, sessionID: String, message: String, status: AgentSessionStatus? = nil, labels: [AgentSessionLabel] = []) {
        self.runID = runID
        self.sessionID = sessionID
        self.message = message
        self.status = status
        self.labels = labels
    }
}

public struct AgentSessionArtifactEvent: Codable, Sendable, Equatable {
    public var runID: String?
    public var sessionID: String
    public var artifactKind: String
    public var path: String
    public var message: String

    public init(runID: String? = nil, sessionID: String, artifactKind: String, path: String, message: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.artifactKind = artifactKind
        self.path = path
        self.message = message
    }
}

public struct AgentProductOSRegistryEvent: Codable, Sendable, Equatable {
    public var runID: String?
    public var sessionID: String
    public var registryKind: String
    public var entryID: String
    public var status: ProductOSRegistryEntryStatus?
    public var message: String

    public init(
        runID: String? = nil,
        sessionID: String,
        registryKind: String,
        entryID: String,
        status: ProductOSRegistryEntryStatus? = nil,
        message: String
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.registryKind = registryKind
        self.entryID = entryID
        self.status = status
        self.message = message
    }
}

public struct AgentAutomationPlaceholderEvent: Codable, Sendable, Equatable {
    public var runID: String?
    public var sessionID: String
    public var trigger: String
    public var message: String

    public init(runID: String? = nil, sessionID: String, trigger: String, message: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.trigger = trigger
        self.message = message
    }
}

public struct AgentGraphMemoryLifecycleEvent: Codable, Sendable, Equatable {
    public var runID: String?
    public var sessionID: String
    public var graphID: String
    public var memoryID: String?
    public var message: String

    public init(runID: String? = nil, sessionID: String, graphID: String = "default", memoryID: String? = nil, message: String) {
        self.runID = runID
        self.sessionID = sessionID
        self.graphID = graphID
        self.memoryID = memoryID
        self.message = message
    }
}
