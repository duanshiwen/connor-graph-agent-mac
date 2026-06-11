import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct ClaudeSDKSidecarRequest: Codable, Sendable, Equatable {
    public var connorRunID: String
    public var connorSessionID: String
    public var groupID: String
    public var prompt: String
    public var cwd: String
    public var permissionMode: AgentPermissionMode
    public var sdkPermissionMode: String
    public var sdkSessionID: String?
    public var ownsProductState: Bool

    public init(
        connorRunID: String,
        connorSessionID: String,
        groupID: String,
        prompt: String,
        cwd: String,
        permissionMode: AgentPermissionMode,
        sdkPermissionMode: String = "bypassPermissions",
        sdkSessionID: String? = nil,
        ownsProductState: Bool = false
    ) {
        self.connorRunID = connorRunID
        self.connorSessionID = connorSessionID
        self.groupID = groupID
        self.prompt = prompt
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.sdkPermissionMode = sdkPermissionMode
        self.sdkSessionID = sdkSessionID
        self.ownsProductState = ownsProductState
    }

    public init(request: AgentChatRequest, workingDirectory: URL, sdkSessionID: String? = nil) {
        self.init(
            connorRunID: request.runID,
            connorSessionID: request.sessionID,
            groupID: request.groupID,
            prompt: request.userMessage,
            cwd: workingDirectory.path,
            permissionMode: request.permissionMode,
            sdkPermissionMode: "bypassPermissions",
            sdkSessionID: sdkSessionID,
            ownsProductState: false
        )
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

public struct ClaudeSDKSidecarRunFailed: Codable, Sendable, Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public enum ClaudeSDKSidecarEvent: Codable, Sendable, Equatable {
    case runStarted(ClaudeSDKSidecarRunStarted)
    case textDelta(ClaudeSDKSidecarTextDelta)
    case textComplete(ClaudeSDKSidecarTextComplete)
    case runCompleted(ClaudeSDKSidecarRunCompleted)
    case runFailed(ClaudeSDKSidecarRunFailed)
}

public protocol ClaudeSDKSidecarTransport: Sendable {
    func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
}

public struct ClaudeSDKSidecarBackend<Transport: ClaudeSDKSidecarTransport>: AgentBackend {
    public var transport: Transport
    public var workingDirectory: URL

    public init(transport: Transport, workingDirectory: URL) {
        self.transport = transport
        self.workingDirectory = workingDirectory
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let sidecarRequest = ClaudeSDKSidecarRequest(request: request, workingDirectory: workingDirectory)
        return AsyncThrowingStream { continuation in
            Task {
                let sidecarEvents = await transport.stream(sidecarRequest)
                for try await event in sidecarEvents {
                    continuation.yield(map(event, request: request))
                }
                continuation.finish()
            }
        }
    }

    private func map(_ event: ClaudeSDKSidecarEvent, request: AgentChatRequest) -> AgentEvent {
        switch event {
        case .runStarted(let payload):
            return .runStarted(AgentRunStartedEvent(run: AgentRun(
                id: request.runID,
                sessionID: request.sessionID,
                groupID: request.groupID,
                status: .running,
                model: "claude-agent-sdk",
                metadata: [
                    "runtime": "claude-sdk-sidecar",
                    "sdk_permission_mode": "bypassPermissions",
                    "sdk_owns_product_state": "false",
                    "sdk_session_id": payload.sdkSessionID ?? ""
                ]
            )))
        case .textDelta(let payload):
            return .textDelta(AgentTextDeltaEvent(
                runID: request.runID,
                sessionID: request.sessionID,
                text: payload.text
            ))
        case .textComplete(let payload):
            return .textComplete(AgentTextCompleteEvent(
                runID: request.runID,
                sessionID: request.sessionID,
                text: payload.text,
                citations: payload.citations,
                contextSnapshot: payload.contextSnapshot
            ))
        case .runCompleted:
            return .runCompleted(AgentRunCompletedEvent(run: AgentRun(
                id: request.runID,
                sessionID: request.sessionID,
                groupID: request.groupID,
                status: .completed,
                completedAt: Date(),
                model: "claude-agent-sdk",
                metadata: ["runtime": "claude-sdk-sidecar"]
            )))
        case .runFailed(let payload):
            return .runFailed(AgentRunFailure(
                runID: request.runID,
                sessionID: request.sessionID,
                message: payload.message
            ))
        }
    }
}
