import Foundation
import ConnorGraphAgent

public enum ClaudeSDKSidecarRequestKind: String, Codable, Sendable, Equatable {
    case fresh
    case resume
    case fork
}

public enum ClaudeSDKSidecarFailureCode: String, Codable, Sendable, Equatable {
    case sdkError = "sdk_error"
    case invalidRequest = "invalid_request"
    case permissionDeferred = "permission_deferred"
    case permissionDenied = "permission_denied"
    case processFailed = "process_failed"
    case cancelled
    case unknown
}

public enum ClaudeSDKSidecarRecoverability: String, Codable, Sendable, Equatable {
    case retryable
    case resumable
    case requiresUserAction = "requires_user_action"
    case terminal
    case unknown
}

public struct ClaudeSDKSidecarRequestOptions: Codable, Sendable, Equatable {
    public var maxTurns: Int?
    public var model: String?
    public var effort: String?
    public var includePartialMessages: Bool
    public var includeHookEvents: Bool
    public var persistSession: Bool
    public var sdkSessionStoreHint: String?
    public var appendSystemPrompt: String?
    public var disallowedTools: [String]?

    public init(
        maxTurns: Int? = nil,
        model: String? = nil,
        effort: String? = nil,
        includePartialMessages: Bool = true,
        includeHookEvents: Bool = true,
        persistSession: Bool = true,
        sdkSessionStoreHint: String? = nil,
        appendSystemPrompt: String? = nil,
        disallowedTools: [String]? = nil
    ) {
        self.maxTurns = maxTurns
        self.model = model
        self.effort = effort
        self.includePartialMessages = includePartialMessages
        self.includeHookEvents = includeHookEvents
        self.persistSession = persistSession
        self.sdkSessionStoreHint = sdkSessionStoreHint
        self.appendSystemPrompt = appendSystemPrompt
        self.disallowedTools = disallowedTools
    }
}

public struct ClaudeSDKSidecarRuntimeDiagnostic: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var status: String
    public var message: String
    public var sdkSessionID: String?
    public var sdkCWD: String?
    public var failureCode: ClaudeSDKSidecarFailureCode?
    public var recoverability: ClaudeSDKSidecarRecoverability?
    public var ownsProductState: Bool

    public init(
        protocolVersion: Int = 2,
        status: String,
        message: String,
        sdkSessionID: String? = nil,
        sdkCWD: String? = nil,
        failureCode: ClaudeSDKSidecarFailureCode? = nil,
        recoverability: ClaudeSDKSidecarRecoverability? = nil,
        ownsProductState: Bool = false
    ) {
        self.protocolVersion = protocolVersion
        self.status = status
        self.message = message
        self.sdkSessionID = sdkSessionID
        self.sdkCWD = sdkCWD
        self.failureCode = failureCode
        self.recoverability = recoverability
        self.ownsProductState = ownsProductState
    }
}

public struct ClaudeSDKSidecarHeartbeat: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var sdkSessionID: String?
    public var sdkCWD: String
    public var timestamp: String
    public var pendingDeferredToolUseCount: Int
    public var ownsProductState: Bool

    public init(
        protocolVersion: Int = 2,
        sdkSessionID: String? = nil,
        sdkCWD: String,
        timestamp: String,
        pendingDeferredToolUseCount: Int = 0,
        ownsProductState: Bool = false
    ) {
        self.protocolVersion = protocolVersion
        self.sdkSessionID = sdkSessionID
        self.sdkCWD = sdkCWD
        self.timestamp = timestamp
        self.pendingDeferredToolUseCount = pendingDeferredToolUseCount
        self.ownsProductState = ownsProductState
    }
}

public struct ClaudeSDKSidecarRequest: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var requestKind: ClaudeSDKSidecarRequestKind
    public var connorRunID: String
    public var connorSessionID: String
    public var groupID: String
    public var prompt: String
    public var cwd: String
    public var permissionMode: AgentPermissionMode
    public var sdkPermissionMode: String
    public var sdkSessionID: String?
    public var forkFromSDKSessionID: String?
    public var options: ClaudeSDKSidecarRequestOptions
    public var ownsProductState: Bool

    public init(
        protocolVersion: Int = 2,
        requestKind: ClaudeSDKSidecarRequestKind = .fresh,
        connorRunID: String,
        connorSessionID: String,
        groupID: String,
        prompt: String,
        cwd: String,
        permissionMode: AgentPermissionMode,
        sdkPermissionMode: String = "bypassPermissions",
        sdkSessionID: String? = nil,
        forkFromSDKSessionID: String? = nil,
        options: ClaudeSDKSidecarRequestOptions = ClaudeSDKSidecarRequestOptions(),
        ownsProductState: Bool = false
    ) {
        self.protocolVersion = protocolVersion
        self.requestKind = requestKind
        self.connorRunID = connorRunID
        self.connorSessionID = connorSessionID
        self.groupID = groupID
        self.prompt = prompt
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.sdkPermissionMode = sdkPermissionMode
        self.sdkSessionID = sdkSessionID
        self.forkFromSDKSessionID = forkFromSDKSessionID
        self.options = options
        self.ownsProductState = ownsProductState
    }

    public init(request: AgentChatRequest, workingDirectory: URL, sdkSessionID: String? = nil) {
        self.init(
            connorRunID: request.runID,
            connorSessionID: request.sessionID,
            groupID: request.groupID,
            prompt: request.normalizedPrompt,
            cwd: workingDirectory.path,
            permissionMode: request.permissionMode,
            sdkPermissionMode: "bypassPermissions",
            sdkSessionID: sdkSessionID,
            options: ClaudeSDKSidecarRequestOptions(
                appendSystemPrompt: AgentInstructionSection.defaultConnorInstruction
            ),
            ownsProductState: false
        )
    }

    public var effectiveRequestKind: ClaudeSDKSidecarRequestKind {
        if forkFromSDKSessionID != nil { return .fork }
        if sdkSessionID != nil { return .resume }
        return requestKind
    }
}

public struct ClaudeSDKSidecarApprovalResolution: Codable, Sendable, Equatable {
    public var connorRunID: String
    public var connorSessionID: String
    public var requestID: String
    public var status: AgentPendingApprovalStatus
    public var outcome: AgentPermissionOutcome
    public var capability: AgentPermissionCapability
    public var toolName: String?
    public var payloadJSON: String
    public var reason: String
    public var actor: String
    public var ownsProductState: Bool

    public init(
        connorRunID: String,
        connorSessionID: String,
        requestID: String,
        status: AgentPendingApprovalStatus,
        outcome: AgentPermissionOutcome? = nil,
        capability: AgentPermissionCapability,
        toolName: String? = nil,
        payloadJSON: String = "{}",
        reason: String,
        actor: String = "human-reviewer",
        ownsProductState: Bool = false
    ) {
        self.connorRunID = connorRunID
        self.connorSessionID = connorSessionID
        self.requestID = requestID
        self.status = status
        self.outcome = outcome ?? Self.outcome(for: status)
        self.capability = capability
        self.toolName = toolName
        self.payloadJSON = payloadJSON
        self.reason = reason
        self.actor = actor
        self.ownsProductState = ownsProductState
    }

    public init(
        approval: AgentPendingApproval,
        status: AgentPendingApprovalStatus,
        reason: String,
        actor: String = "human-reviewer"
    ) {
        self.init(
            connorRunID: approval.runID,
            connorSessionID: approval.sessionID,
            requestID: approval.requestID,
            status: status,
            capability: approval.capability,
            toolName: approval.toolName,
            payloadJSON: approval.payloadJSON,
            reason: reason,
            actor: actor,
            ownsProductState: false
        )
    }

    public static func outcome(for status: AgentPendingApprovalStatus) -> AgentPermissionOutcome {
        switch status {
        case .approved: return .approved
        case .denied, .cancelled: return .denied
        case .pending: return .needsApproval
        }
    }
}

public struct ClaudeSDKSidecarCancelCommand: Codable, Sendable, Equatable {
    public var connorRunID: String
    public var connorSessionID: String
    public var reason: String

    public init(connorRunID: String, connorSessionID: String, reason: String = "cancelled by Connor") {
        self.connorRunID = connorRunID
        self.connorSessionID = connorSessionID
        self.reason = reason
    }
}

public enum ClaudeSDKSidecarCommand: Codable, Sendable, Equatable {
    case start(ClaudeSDKSidecarRequest)
    case approvalResolved(ClaudeSDKSidecarApprovalResolution)
    case cancel(ClaudeSDKSidecarCancelCommand)

    private enum CodingKeys: String, CodingKey {
        case start
        case approvalResolved
        case cancel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.start) {
            self = .start(try container.decode(ClaudeSDKSidecarRequest.self, forKey: .start))
        } else if container.contains(.approvalResolved) {
            self = .approvalResolved(try container.decode(ClaudeSDKSidecarApprovalResolution.self, forKey: .approvalResolved))
        } else if container.contains(.cancel) {
            self = .cancel(try container.decode(ClaudeSDKSidecarCancelCommand.self, forKey: .cancel))
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected one Claude SDK sidecar command key."
            ))
        }
    }

    public var commandName: String {
        switch self {
        case .start: return "start"
        case .approvalResolved: return "approvalResolved"
        case .cancel: return "cancel"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let payload):
            try container.encode(payload, forKey: .start)
        case .approvalResolved(let payload):
            try container.encode(payload, forKey: .approvalResolved)
        case .cancel(let payload):
            try container.encode(payload, forKey: .cancel)
        }
    }
}

public struct ClaudeSDKSidecarRunStarted: Codable, Sendable, Equatable {
    public var sdkSessionID: String?

    public init(sdkSessionID: String? = nil) {
        self.sdkSessionID = sdkSessionID
    }
}

public struct ClaudeSDKSidecarTextDelta: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ClaudeSDKSidecarTextComplete: Codable, Sendable, Equatable {
    public var text: String
    public var citations: [String]
    public var contextSnapshot: String?

    public init(text: String, citations: [String] = [], contextSnapshot: String? = nil) {
        self.text = text
        self.citations = citations
        self.contextSnapshot = contextSnapshot
    }
}

public struct ClaudeSDKSidecarRunCompleted: Codable, Sendable, Equatable {
    public init() {}
}

public struct ClaudeSDKSidecarToolUseRequested: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var name: String
    public var inputJSON: String

    public init(toolCallID: String, name: String, inputJSON: String = "{}") {
        self.toolCallID = toolCallID
        self.name = name
        self.inputJSON = inputJSON
    }
}

public struct ClaudeSDKSidecarPermissionRequested: Codable, Sendable, Equatable {
    public var requestID: String
    public var capability: AgentPermissionCapability
    public var toolName: String?
    public var payloadJSON: String

    public init(requestID: String, capability: AgentPermissionCapability, toolName: String? = nil, payloadJSON: String = "{}") {
        self.requestID = requestID
        self.capability = capability
        self.toolName = toolName
        self.payloadJSON = payloadJSON
    }
}

public struct ClaudeSDKSidecarResumeAccepted: Codable, Sendable, Equatable {
    public var requestID: String
    public var toolName: String?
    public var message: String

    public init(requestID: String, toolName: String? = nil, message: String = "") {
        self.requestID = requestID
        self.toolName = toolName
        self.message = message
    }
}

public struct ClaudeSDKSidecarResumeRejected: Codable, Sendable, Equatable {
    public var requestID: String
    public var toolName: String?
    public var reason: String

    public init(requestID: String, toolName: String? = nil, reason: String) {
        self.requestID = requestID
        self.toolName = toolName
        self.reason = reason
    }
}

public struct ClaudeSDKSidecarToolUseStarted: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var name: String

    public init(toolCallID: String, name: String) {
        self.toolCallID = toolCallID
        self.name = name
    }
}

public struct ClaudeSDKSidecarToolUseCompleted: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var name: String
    public var contentText: String
    public var contentJSON: String?
    public var isError: Bool

    public init(toolCallID: String, name: String, contentText: String, contentJSON: String? = nil, isError: Bool = false) {
        self.toolCallID = toolCallID
        self.name = name
        self.contentText = contentText
        self.contentJSON = contentJSON
        self.isError = isError
    }
}

public struct ClaudeSDKSidecarRunFailed: Codable, Sendable, Equatable {
    public var message: String
    public var code: ClaudeSDKSidecarFailureCode
    public var recoverability: ClaudeSDKSidecarRecoverability

    private enum CodingKeys: String, CodingKey {
        case message
        case code
        case recoverability
    }

    public init(
        message: String,
        code: ClaudeSDKSidecarFailureCode = .unknown,
        recoverability: ClaudeSDKSidecarRecoverability = .unknown
    ) {
        self.message = message
        self.code = code
        self.recoverability = recoverability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decode(String.self, forKey: .message)
        self.code = try container.decodeIfPresent(ClaudeSDKSidecarFailureCode.self, forKey: .code) ?? .unknown
        self.recoverability = try container.decodeIfPresent(ClaudeSDKSidecarRecoverability.self, forKey: .recoverability) ?? .unknown
    }
}

public struct ClaudeSDKSidecarHealth: Codable, Sendable, Equatable {
    public var status: String
    public var pendingDeferredToolUseCount: Int
    public var timestamp: String
    public var ownsProductState: Bool
    public var protocolVersion: Int
    public var capabilities: [String]

    private enum CodingKeys: String, CodingKey {
        case status
        case pendingDeferredToolUseCount
        case timestamp
        case ownsProductState
        case protocolVersion
        case capabilities
    }

    public init(
        status: String,
        pendingDeferredToolUseCount: Int = 0,
        timestamp: String,
        ownsProductState: Bool = false,
        protocolVersion: Int = 2,
        capabilities: [String] = []
    ) {
        self.status = status
        self.pendingDeferredToolUseCount = pendingDeferredToolUseCount
        self.timestamp = timestamp
        self.ownsProductState = ownsProductState
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(String.self, forKey: .status)
        self.pendingDeferredToolUseCount = try container.decodeIfPresent(Int.self, forKey: .pendingDeferredToolUseCount) ?? 0
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.ownsProductState = try container.decodeIfPresent(Bool.self, forKey: .ownsProductState) ?? false
        self.protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 2
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}

public enum ClaudeSDKSidecarEvent: Codable, Sendable, Equatable {
    case runStarted(ClaudeSDKSidecarRunStarted)
    case textDelta(ClaudeSDKSidecarTextDelta)
    case textComplete(ClaudeSDKSidecarTextComplete)
    case runCompleted(ClaudeSDKSidecarRunCompleted)
    case toolUseRequested(ClaudeSDKSidecarToolUseRequested)
    case permissionRequested(ClaudeSDKSidecarPermissionRequested)
    case resumeAccepted(ClaudeSDKSidecarResumeAccepted)
    case resumeRejected(ClaudeSDKSidecarResumeRejected)
    case toolUseStarted(ClaudeSDKSidecarToolUseStarted)
    case toolUseCompleted(ClaudeSDKSidecarToolUseCompleted)
    case runFailed(ClaudeSDKSidecarRunFailed)
    case sidecarHealth(ClaudeSDKSidecarHealth)
    case runtimeDiagnostic(ClaudeSDKSidecarRuntimeDiagnostic)
    case heartbeat(ClaudeSDKSidecarHeartbeat)

    private enum CodingKeys: String, CodingKey {
        case runStarted
        case textDelta
        case textComplete
        case runCompleted
        case toolUseRequested
        case permissionRequested
        case resumeAccepted
        case resumeRejected
        case toolUseStarted
        case toolUseCompleted
        case runFailed
        case sidecarHealth
        case runtimeDiagnostic
        case heartbeat
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.runStarted) {
            self = .runStarted(try container.decode(ClaudeSDKSidecarRunStarted.self, forKey: .runStarted))
        } else if container.contains(.textDelta) {
            self = .textDelta(try container.decode(ClaudeSDKSidecarTextDelta.self, forKey: .textDelta))
        } else if container.contains(.textComplete) {
            self = .textComplete(try container.decode(ClaudeSDKSidecarTextComplete.self, forKey: .textComplete))
        } else if container.contains(.runCompleted) {
            self = .runCompleted(try container.decode(ClaudeSDKSidecarRunCompleted.self, forKey: .runCompleted))
        } else if container.contains(.toolUseRequested) {
            self = .toolUseRequested(try container.decode(ClaudeSDKSidecarToolUseRequested.self, forKey: .toolUseRequested))
        } else if container.contains(.permissionRequested) {
            self = .permissionRequested(try container.decode(ClaudeSDKSidecarPermissionRequested.self, forKey: .permissionRequested))
        } else if container.contains(.resumeAccepted) {
            self = .resumeAccepted(try container.decode(ClaudeSDKSidecarResumeAccepted.self, forKey: .resumeAccepted))
        } else if container.contains(.resumeRejected) {
            self = .resumeRejected(try container.decode(ClaudeSDKSidecarResumeRejected.self, forKey: .resumeRejected))
        } else if container.contains(.toolUseStarted) {
            self = .toolUseStarted(try container.decode(ClaudeSDKSidecarToolUseStarted.self, forKey: .toolUseStarted))
        } else if container.contains(.toolUseCompleted) {
            self = .toolUseCompleted(try container.decode(ClaudeSDKSidecarToolUseCompleted.self, forKey: .toolUseCompleted))
        } else if container.contains(.runFailed) {
            self = .runFailed(try container.decode(ClaudeSDKSidecarRunFailed.self, forKey: .runFailed))
        } else if container.contains(.sidecarHealth) {
            self = .sidecarHealth(try container.decode(ClaudeSDKSidecarHealth.self, forKey: .sidecarHealth))
        } else if container.contains(.runtimeDiagnostic) {
            self = .runtimeDiagnostic(try container.decode(ClaudeSDKSidecarRuntimeDiagnostic.self, forKey: .runtimeDiagnostic))
        } else if container.contains(.heartbeat) {
            self = .heartbeat(try container.decode(ClaudeSDKSidecarHeartbeat.self, forKey: .heartbeat))
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected one Claude SDK sidecar event key."
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .runStarted(let payload):
            try container.encode(payload, forKey: .runStarted)
        case .textDelta(let payload):
            try container.encode(payload, forKey: .textDelta)
        case .textComplete(let payload):
            try container.encode(payload, forKey: .textComplete)
        case .runCompleted(let payload):
            try container.encode(payload, forKey: .runCompleted)
        case .toolUseRequested(let payload):
            try container.encode(payload, forKey: .toolUseRequested)
        case .permissionRequested(let payload):
            try container.encode(payload, forKey: .permissionRequested)
        case .resumeAccepted(let payload):
            try container.encode(payload, forKey: .resumeAccepted)
        case .resumeRejected(let payload):
            try container.encode(payload, forKey: .resumeRejected)
        case .toolUseStarted(let payload):
            try container.encode(payload, forKey: .toolUseStarted)
        case .toolUseCompleted(let payload):
            try container.encode(payload, forKey: .toolUseCompleted)
        case .runFailed(let payload):
            try container.encode(payload, forKey: .runFailed)
        case .sidecarHealth(let payload):
            try container.encode(payload, forKey: .sidecarHealth)
        case .runtimeDiagnostic(let payload):
            try container.encode(payload, forKey: .runtimeDiagnostic)
        case .heartbeat(let payload):
            try container.encode(payload, forKey: .heartbeat)
        }
    }
}

