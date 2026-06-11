import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum GovernedClaudeSDKSidecarRuntimeError: Error, Sendable, Equatable, LocalizedError {
    case unsafePermissionMode(AgentPermissionMode)
    case approvalStillPending(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePermissionMode(let mode):
            return "Governed Claude SDK sidecar runtime refuses unsafe permission mode: \(mode.rawValue)."
        case .approvalStillPending(let requestID):
            return "Cannot resume sidecar with a pending approval decision: \(requestID)."
        }
    }
}

/// Product-level bridge for the persistent Claude SDK sidecar path.
///
/// Connor owns sessions, permission decisions, audit, pending approvals, and graph memory.
/// This runtime only forwards Connor-normalized prompts and Connor-owned approval resolutions
/// to the external SDK engine over a persistent command transport.
public final class GovernedClaudeSDKSidecarRuntime<Transport: ClaudeSDKSidecarSessionTransport>: AgentBackend, @unchecked Sendable {
    public let transport: Transport
    public let workingDirectory: URL
    public let permissionMode: AgentPermissionMode

    public init(
        transport: Transport,
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite
    ) throws {
        guard permissionMode != .allowAll else {
            throw GovernedClaudeSDKSidecarRuntimeError.unsafePermissionMode(permissionMode)
        }
        self.transport = transport
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let safeRequest = AgentChatRequest(
            runID: request.runID,
            sessionID: request.sessionID,
            groupID: request.groupID,
            userMessage: request.userMessage,
            permissionMode: permissionMode
        )
        let sidecarRequest = ClaudeSDKSidecarRequest(request: safeRequest, workingDirectory: workingDirectory)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let sidecarEvents = await transport.start(sidecarRequest)
                    for try await event in sidecarEvents {
                        if let mapped = ClaudeSDKSidecarEventMapper.map(event, request: safeRequest) {
                            continuation.yield(mapped)
                        }
                        if event.isTerminalForConnorSubmit {
                            await transport.cancel()
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func abort(runID: String) {
        Task { await transport.cancel() }
    }

    public func resolveApproval(
        _ approval: AgentPendingApproval,
        status: AgentPendingApprovalStatus,
        reason: String,
        actor: String = "human-reviewer"
    ) async throws {
        guard status != .pending else {
            throw GovernedClaudeSDKSidecarRuntimeError.approvalStillPending(approval.requestID)
        }
        let resolution = ClaudeSDKSidecarApprovalResolution(
            approval: approval,
            status: status,
            reason: reason,
            actor: actor
        )
        try await transport.send(.approvalResolved(resolution))
    }

    public func cancel() async {
        await transport.cancel()
    }
}

