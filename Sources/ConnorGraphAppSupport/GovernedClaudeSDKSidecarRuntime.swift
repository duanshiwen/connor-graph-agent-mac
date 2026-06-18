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
    public let instructionAppendix: String
    public let runtimeStore: AppClaudeSDKSidecarRuntimeStore?
    public let thinkingLevel: AppLLMThinkingLevel

    public init(
        transport: Transport,
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite,
        instructionAppendix: String = "",
        runtimeStore: AppClaudeSDKSidecarRuntimeStore? = nil,
        thinkingLevel: AppLLMThinkingLevel = .defaultLevel
    ) throws {
        guard permissionMode != .allowAll else {
            throw GovernedClaudeSDKSidecarRuntimeError.unsafePermissionMode(permissionMode)
        }
        self.transport = transport
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.instructionAppendix = instructionAppendix
        self.runtimeStore = runtimeStore
        self.thinkingLevel = thinkingLevel
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let effectivePermissionMode = request.permissionMode == .trustedWrite ? .trustedWrite : permissionMode
        let safeRequest = AgentChatRequest(
            runID: request.runID,
            sessionID: request.sessionID,
            groupID: request.groupID,
            userMessage: request.userMessage,
            sessionSummary: request.sessionSummary,
            recentMessages: request.recentMessages,
            permissionMode: effectivePermissionMode,
            attachmentRefs: request.attachmentRefs,
            attachmentContextPlan: request.attachmentContextPlan,
            anchorState: request.anchorState,
            skillInstructions: request.skillInstructions,
            activeSkillSlug: request.activeSkillSlug,
            activeSkillDisplayName: request.activeSkillDisplayName
        )
        let resumeSDKSessionID = (try? runtimeStore?.load(connorSessionID: safeRequest.sessionID))?.sdkSessionID
        let sidecarRequest = ClaudeSDKSidecarRequest(
            request: safeRequest,
            workingDirectory: workingDirectory,
            sdkSessionID: resumeSDKSessionID,
            instructionAppendix: instructionAppendix,
            effort: thinkingLevel.effortValue
        )
        try? updateRuntimeRecord(
            sessionID: safeRequest.sessionID,
            groupID: safeRequest.groupID,
            runID: safeRequest.runID,
            status: .starting,
            sdkSessionID: sidecarRequest.sdkSessionID,
            pendingApprovalRequestID: nil,
            lastError: nil,
            protocolVersion: sidecarRequest.protocolVersion,
            sdkCWD: sidecarRequest.cwd,
            sdkSessionStoreHint: sidecarRequest.options.sdkSessionStoreHint,
            forkedFromSDKSessionID: sidecarRequest.forkFromSDKSessionID
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
                        lastError: String(describing: error),
                        failureCode: .processFailed,
                        recoverability: .retryable
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func abort(runID: String) {
        Task {
            let record = try? runtimeStore?.loadByRunID(runID)
            if let record {
                try? await transport.send(.cancel(ClaudeSDKSidecarCancelCommand(
                    connorRunID: runID,
                    connorSessionID: record.connorSessionID,
                    reason: "cancelled by Connor"
                )))
                try? updateRuntimeRecord(
                    sessionID: record.connorSessionID,
                    groupID: record.groupID,
                    runID: runID,
                    status: .cancelled,
                    sdkSessionID: record.sdkSessionID,
                    lastError: "cancelled by Connor",
                    failureCode: .cancelled,
                    recoverability: .terminal
                )
            }
            await transport.cancel()
        }
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
                lastError: payload.message,
                failureCode: payload.code,
                recoverability: payload.recoverability
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
        case .runtimeDiagnostic(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: payload.status == "failed" ? .failed : .running,
                sdkSessionID: payload.sdkSessionID,
                lastError: payload.failureCode == nil ? nil : payload.message,
                protocolVersion: payload.protocolVersion,
                sdkCWD: payload.sdkCWD,
                lastDiagnosticMessage: payload.message,
                failureCode: payload.failureCode,
                recoverability: payload.recoverability
            )
        case .heartbeat(let payload):
            try updateRuntimeRecord(
                sessionID: request.sessionID,
                groupID: request.groupID,
                runID: request.runID,
                status: .running,
                sdkSessionID: payload.sdkSessionID,
                protocolVersion: payload.protocolVersion,
                sdkCWD: payload.sdkCWD,
                lastHeartbeatAt: Date()
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
        lastError: String? = nil,
        protocolVersion: Int? = nil,
        sdkCWD: String? = nil,
        sdkSessionStoreHint: String? = nil,
        forkedFromSDKSessionID: String? = nil,
        lastHeartbeatAt: Date? = nil,
        lastDiagnosticMessage: String? = nil,
        failureCode: ClaudeSDKSidecarFailureCode? = nil,
        recoverability: ClaudeSDKSidecarRecoverability? = nil
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
        if let protocolVersion { record.protocolVersion = protocolVersion }
        if let sdkCWD { record.sdkCWD = sdkCWD }
        if let sdkSessionStoreHint { record.sdkSessionStoreHint = sdkSessionStoreHint }
        if let forkedFromSDKSessionID { record.forkedFromSDKSessionID = forkedFromSDKSessionID }
        if let lastHeartbeatAt { record.lastHeartbeatAt = lastHeartbeatAt }
        if let lastDiagnosticMessage { record.lastDiagnosticMessage = lastDiagnosticMessage }
        if let failureCode { record.failureCode = failureCode }
        if let recoverability { record.recoverability = recoverability }
        if let sdkSessionID { record.sdkSessionID = sdkSessionID }
        try runtimeStore.save(record)
    }
}

