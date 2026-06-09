import Foundation
import ConnorGraphCore

public protocol AgentAuditLog: Sendable {
    func record(_ event: AgentAuditEvent) async
}

public actor InMemoryAgentAuditLog: AgentAuditLog {
    public private(set) var events: [AgentAuditEvent] = []

    public init() {}

    public func record(_ event: AgentAuditEvent) async {
        events.append(event)
    }
}

public actor AgentPolicyEngine: Sendable {
    public let permissionMode: AgentPermissionMode
    private let auditLog: any AgentAuditLog

    public init(permissionMode: AgentPermissionMode, auditLog: any AgentAuditLog = InMemoryAgentAuditLog()) {
        self.permissionMode = permissionMode
        self.auditLog = auditLog
    }

    public func evaluate(
        capability: AgentPermissionCapability,
        runID: String,
        sessionID: String,
        toolName: String? = nil,
        payloadJSON: String = "{}"
    ) async -> AgentPermissionDecision {
        let request = AgentPermissionRequest(
            runID: runID,
            sessionID: sessionID,
            capability: capability,
            toolName: toolName,
            payloadJSON: payloadJSON
        )
        let outcome = outcome(for: capability)
        let decision = AgentPermissionDecision(
            requestID: request.id,
            runID: runID,
            sessionID: sessionID,
            capability: capability,
            outcome: outcome,
            reason: reason(for: capability, outcome: outcome)
        )
        await auditLog.record(AgentAuditEvent(
            runID: runID,
            sessionID: sessionID,
            eventType: .permissionDecision,
            capability: capability,
            toolName: toolName,
            decision: decision,
            payloadJSON: payloadJSON
        ))
        return decision
    }

    private func outcome(for capability: AgentPermissionCapability) -> AgentPermissionOutcome {
        switch permissionMode {
        case .allowAll:
            return .approved
        case .readOnly:
            switch capability {
            case .readGraph, .readSession, .modelCall:
                return .approved
            case .proposeGraphWrite, .commitGraphWrite, .invalidateGraphFact, .deleteGraphObject, .externalNetwork, .costlyModelCall:
                return .denied
            }
        case .askToWrite:
            switch capability {
            case .readGraph, .readSession, .modelCall, .proposeGraphWrite:
                return .approved
            case .commitGraphWrite, .invalidateGraphFact, .deleteGraphObject, .externalNetwork, .costlyModelCall:
                return .needsApproval
            }
        case .trustedWrite:
            switch capability {
            case .readGraph, .readSession, .modelCall, .proposeGraphWrite, .commitGraphWrite:
                return .approved
            case .invalidateGraphFact, .deleteGraphObject, .externalNetwork, .costlyModelCall:
                return .needsApproval
            }
        }
    }

    private func reason(for capability: AgentPermissionCapability, outcome: AgentPermissionOutcome) -> String {
        "\(permissionMode.rawValue) policy \(outcome.rawValue) capability \(capability.rawValue)"
    }
}
