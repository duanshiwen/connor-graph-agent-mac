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
    public let runtimeStore: AppClaudeSDKSidecarRuntimeStore?

    public init(
        transport: Transport,
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite,
        runtimeStore: AppClaudeSDKSidecarRuntimeStore? = nil
    ) throws {
        guard permissionMode != .allowAll else {
            throw GovernedClaudeSDKSidecarRuntimeError.unsafePermissionMode(permissionMode)
        }
        self.transport = transport
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.runtimeStore = runtimeStore
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let safeRequest = AgentChatRequest(
            runID: request.runID,
            sessionID: request.sessionID,
            groupID: request.groupID,
            userMessage: request.userMessage,
            sessionSummary: request.sessionSummary,
            recentMessages: request.recentMessages,
            permissionMode: permissionMode
        )
        let resumeSDKSessionID = (try? runtimeStore?.load(connorSessionID: safeRequest.sessionID))?.sdkSessionID
        let sidecarRequest = ClaudeSDKSidecarRequest(
            request: safeRequest,
            workingDirectory: workingDirectory,
            sdkSessionID: resumeSDKSessionID
        )
        try? updateRuntimeRecord(
            sessionID: safeRequest.sessionID,
            groupID: safeRequest.groupID,
            runID: safeRequest.runID,
            status: .starting,
            sdkSessionID: sidecarRequest.sdkSessionID,
            pendingApprovalRequestID: nil,
            lastError: nil
        )
        let finalSidecarRequest = sidecarRequest
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let sidecarEvents = await transport.start(finalSidecarRequest)
                    for try await event in sidecarEvents {
                        try? updateRuntimeRecord(for: event, request: safeRequest)
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
                    try? updateRuntimeRecord(
                        sessionID: safeRequest.sessionID,
                        groupID: safeRequest.groupID,
                        runID: safeRequest.runID,
                        status: .failed,
                        sdkSessionID: finalSidecarRequest.sdkSessionID,
                        lastError: String(describing: error)
                    )
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

    private func updateRuntimeRecord(for event: ClaudeSDKSidecarEvent, request: AgentChatRequest) throws {
        switch event {
        case .runStarted(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .running,
                sdkSessionID: payload.sdkSessionID,
                pendingApprovalRequestID: nil,
                lastError: nil
            )
        case .permissionRequested(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .permissionPending,
                pendingApprovalRequestID: payload.requestID,
                lastError: nil
            )
        case .resumeAccepted:
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .running,
                pendingApprovalRequestID: nil,
                lastError: nil
            )
        case .resumeRejected(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .failed,
                pendingApprovalRequestID: nil,
                lastError: payload.reason
            )
        case .runFailed(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .failed,
                pendingApprovalRequestID: nil,
                lastError: payload.message
            )
        case .runCompleted:
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .ready,
                pendingApprovalRequestID: nil,
                lastError: nil
            )
        case .textDelta, .textComplete, .toolUseRequested, .toolUseStarted, .toolUseCompleted, .sidecarHealth:
            break
        }
    }

    private func updateRuntimeRecord(
        sessionID: String,
        groupID: String,
        runID: String,
        status: ClaudeSDKSidecarRuntimeStatus,
        sdkSessionID: String? = nil,
        pendingApprovalRequestID: String? = nil,
        lastError: String? = nil
    ) throws {
        guard let runtimeStore else { return }
        var record = try runtimeStore.load(connorSessionID: sessionID) ?? ClaudeSDKSidecarRuntimeRecord(
            connorSessionID: sessionID,
            groupID: groupID
        )
        record.groupID = groupID
        record.lastRunID = runID
        record.status = status
        record.pendingApprovalRequestID = pendingApprovalRequestID
        record.lastError = lastError
        if let sdkSessionID { record.sdkSessionID = sdkSessionID }
        try runtimeStore.save(record)
    }
}

