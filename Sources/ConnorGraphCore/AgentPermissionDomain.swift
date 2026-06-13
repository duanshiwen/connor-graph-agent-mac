import Foundation

public enum AgentPermissionCapability: String, Codable, Sendable, Equatable {
    case readGraph
    case readSession
    case proposeGraphWrite
    case commitGraphWrite
    case invalidateGraphStatement
    case deleteGraphObject
    case externalNetwork
    case modelCall
    case costlyModelCall
    case readWorkspaceFile
    case listWorkspaceFiles
    case searchWorkspaceFiles
    case writeWorkspaceFile
    case editWorkspaceFile
    case deleteWorkspaceFile
    case computeScientific
    case runReadOnlyShellCommand
    case runWorkspaceShellCommand
    case runNetworkShellCommand
    case runDestructiveShellCommand
}

public enum AgentPermissionMode: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case readOnly
    case askToWrite
    case trustedWrite
    case allowAll

    public var displayName: String {
        switch self {
        case .readOnly: "只读"
        case .askToWrite: "询问后编辑"
        case .trustedWrite: "信任编辑"
        case .allowAll: "全部允许"
        }
    }
}

public enum AgentPermissionOutcome: String, Codable, Sendable, Equatable {
    case approved
    case denied
    case needsApproval
}

public struct AgentPermissionRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var sessionID: String
    public var capability: AgentPermissionCapability
    public var toolName: String?
    public var payloadJSON: String

    public init(
        id: String = UUID().uuidString,
        runID: String,
        sessionID: String,
        capability: AgentPermissionCapability,
        toolName: String? = nil,
        payloadJSON: String = "{}"
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.capability = capability
        self.toolName = toolName
        self.payloadJSON = payloadJSON
    }
}

public struct AgentPermissionDecision: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var requestID: String
    public var runID: String
    public var sessionID: String
    public var capability: AgentPermissionCapability
    public var outcome: AgentPermissionOutcome
    public var reason: String

    public init(
        id: String = UUID().uuidString,
        requestID: String,
        runID: String,
        sessionID: String,
        capability: AgentPermissionCapability,
        outcome: AgentPermissionOutcome,
        reason: String
    ) {
        self.id = id
        self.requestID = requestID
        self.runID = runID
        self.sessionID = sessionID
        self.capability = capability
        self.outcome = outcome
        self.reason = reason
    }
}

public enum AgentPendingApprovalStatus: String, Codable, Sendable, Equatable {
    case pending
    case approved
    case denied
    case cancelled
}

public struct AgentPendingApproval: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var requestID: String
    public var runID: String
    public var sessionID: String
    public var capability: AgentPermissionCapability
    public var toolName: String?
    public var payloadJSON: String
    public var status: AgentPendingApprovalStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        requestID: String,
        runID: String,
        sessionID: String,
        capability: AgentPermissionCapability,
        toolName: String? = nil,
        payloadJSON: String = "{}",
        status: AgentPendingApprovalStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.requestID = requestID
        self.runID = runID
        self.sessionID = sessionID
        self.capability = capability
        self.toolName = toolName
        self.payloadJSON = payloadJSON
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AgentAuditEventType: String, Codable, Sendable, Equatable {
    case permissionDecision
    case toolStarted
    case toolFinished
    case toolFailed
    case graphWriteCandidateApproved
    case graphWriteCandidateRejected
    case graphWriteValidationStarted
    case graphWriteValidationFinished
    case graphWriteValidationFailed
    case graphWriteCommitStarted
    case graphWriteCommitFinished
    case graphWriteCommitFailed
    case localFileReadStarted
    case localFileReadFinished
    case localFileReadFailed
    case localFileWriteStarted
    case localFileWriteFinished
    case localFileWriteFailed
    case localShellStarted
    case localShellFinished
    case localShellFailed
    case localWorkspacePolicyDenied
}

public struct AgentAuditEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var sessionID: String
    public var eventType: AgentAuditEventType
    public var actor: String
    public var capability: AgentPermissionCapability?
    public var toolName: String?
    public var decision: AgentPermissionDecision?
    public var payloadJSON: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        runID: String,
        sessionID: String,
        eventType: AgentAuditEventType,
        actor: String = "agent-runtime",
        capability: AgentPermissionCapability? = nil,
        toolName: String? = nil,
        decision: AgentPermissionDecision? = nil,
        payloadJSON: String = "{}",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.eventType = eventType
        self.actor = actor
        self.capability = capability
        self.toolName = toolName
        self.decision = decision
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}
