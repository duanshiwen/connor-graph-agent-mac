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

    public init(message: String) {
        self.message = message
    }
}

public enum ClaudeSDKSidecarEvent: Codable, Sendable, Equatable {
    case runStarted(ClaudeSDKSidecarRunStarted)
    case textDelta(ClaudeSDKSidecarTextDelta)
    case textComplete(ClaudeSDKSidecarTextComplete)
    case runCompleted(ClaudeSDKSidecarRunCompleted)
    case toolUseRequested(ClaudeSDKSidecarToolUseRequested)
    case permissionRequested(ClaudeSDKSidecarPermissionRequested)
    case toolUseStarted(ClaudeSDKSidecarToolUseStarted)
    case toolUseCompleted(ClaudeSDKSidecarToolUseCompleted)
    case runFailed(ClaudeSDKSidecarRunFailed)

    private enum CodingKeys: String, CodingKey {
        case runStarted
        case textDelta
        case textComplete
        case runCompleted
        case toolUseRequested
        case permissionRequested
        case toolUseStarted
        case toolUseCompleted
        case runFailed
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
        } else if container.contains(.toolUseStarted) {
            self = .toolUseStarted(try container.decode(ClaudeSDKSidecarToolUseStarted.self, forKey: .toolUseStarted))
        } else if container.contains(.toolUseCompleted) {
            self = .toolUseCompleted(try container.decode(ClaudeSDKSidecarToolUseCompleted.self, forKey: .toolUseCompleted))
        } else if container.contains(.runFailed) {
            self = .runFailed(try container.decode(ClaudeSDKSidecarRunFailed.self, forKey: .runFailed))
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
        case .toolUseStarted(let payload):
            try container.encode(payload, forKey: .toolUseStarted)
        case .toolUseCompleted(let payload):
            try container.encode(payload, forKey: .toolUseCompleted)
        case .runFailed(let payload):
            try container.encode(payload, forKey: .runFailed)
        }
    }
}

public protocol ClaudeSDKSidecarTransport: Sendable {
    func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
}

public enum ClaudeSDKSidecarProcessTransportError: Error, Sendable, Equatable, LocalizedError {
    case missingNewlineTerminator
    case nonZeroExit(code: Int32, stderr: String)
    case invalidJSONLine(String)

    public var errorDescription: String? {
        switch self {
        case .missingNewlineTerminator:
            return "Claude SDK sidecar request JSONL payload is missing a newline terminator."
        case .nonZeroExit(let code, let stderr):
            return "Claude SDK sidecar exited with status \(code): \(stderr)"
        case .invalidJSONLine(let line):
            return "Claude SDK sidecar emitted an invalid JSONL event: \(line)"
        }
    }
}

public struct ClaudeSDKSidecarProcessTransport: ClaudeSDKSidecarTransport {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectoryURL: URL?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }

    public func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        let executableURL = executableURL
        let arguments = arguments
        let environment = environment
        let currentDirectoryURL = currentDirectoryURL

        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let events = try runSidecarProcess(
                        request: request,
                        executableURL: executableURL,
                        arguments: arguments,
                        environment: environment,
                        currentDirectoryURL: currentDirectoryURL
                    )
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private func runSidecarProcess(
    request: ClaudeSDKSidecarRequest,
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    currentDirectoryURL: URL?
) throws -> [ClaudeSDKSidecarEvent] {
    let encoder = JSONEncoder()
    var requestData = try encoder.encode(request)
    requestData.append(0x0A)

    guard requestData.last == 0x0A else {
        throw ClaudeSDKSidecarProcessTransportError.missingNewlineTerminator
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL ?? URL(fileURLWithPath: request.cwd, isDirectory: true)

    var processEnvironment = ProcessInfo.processInfo.environment
    environment.forEach { key, value in processEnvironment[key] = value }
    process.environment = processEnvironment

    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    stdin.fileHandleForWriting.write(requestData)
    try? stdin.fileHandleForWriting.close()
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw ClaudeSDKSidecarProcessTransportError.nonZeroExit(
            code: process.terminationStatus,
            stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    let output = String(data: stdoutData, encoding: .utf8) ?? ""
    let decoder = JSONDecoder()
    return try output
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { line in
            let lineText = String(line)
            guard let lineData = lineText.data(using: .utf8) else {
                throw ClaudeSDKSidecarProcessTransportError.invalidJSONLine(lineText)
            }
            do {
                return try decoder.decode(ClaudeSDKSidecarEvent.self, from: lineData)
            } catch {
                throw ClaudeSDKSidecarProcessTransportError.invalidJSONLine(lineText)
            }
        }
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
        case .toolUseRequested(let payload):
            return .toolRequested(AgentToolCall(
                id: payload.toolCallID,
                runID: request.runID,
                sessionID: request.sessionID,
                name: payload.name,
                argumentsJSON: payload.inputJSON
            ))
        case .permissionRequested(let payload):
            return .permissionRequested(AgentPermissionRequest(
                id: payload.requestID,
                runID: request.runID,
                sessionID: request.sessionID,
                capability: payload.capability,
                toolName: payload.toolName,
                payloadJSON: payload.payloadJSON
            ))
        case .toolUseStarted(let payload):
            return .toolStarted(AgentToolCall(
                id: payload.toolCallID,
                runID: request.runID,
                sessionID: request.sessionID,
                name: payload.name,
                argumentsJSON: "{}"
            ))
        case .toolUseCompleted(let payload):
            if payload.isError {
                return .toolFailed(AgentToolFailure(
                    runID: request.runID,
                    sessionID: request.sessionID,
                    toolCallID: payload.toolCallID,
                    toolName: payload.name,
                    message: payload.contentText
                ))
            }
            return .toolFinished(AgentToolResult(
                runID: request.runID,
                sessionID: request.sessionID,
                toolCallID: payload.toolCallID,
                toolName: payload.name,
                contentText: payload.contentText,
                contentJSON: payload.contentJSON
            ))
        case .runFailed(let payload):
            return .runFailed(AgentRunFailure(
                runID: request.runID,
                sessionID: request.sessionID,
                message: payload.message
            ))
        }
    }
}
