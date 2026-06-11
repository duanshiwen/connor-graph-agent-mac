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

public enum ClaudeSDKSidecarCommand: Codable, Sendable, Equatable {
    case start(ClaudeSDKSidecarRequest)
    case approvalResolved(ClaudeSDKSidecarApprovalResolution)

    private enum CodingKeys: String, CodingKey {
        case start
        case approvalResolved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.start) {
            self = .start(try container.decode(ClaudeSDKSidecarRequest.self, forKey: .start))
        } else if container.contains(.approvalResolved) {
            self = .approvalResolved(try container.decode(ClaudeSDKSidecarApprovalResolution.self, forKey: .approvalResolved))
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
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let payload):
            try container.encode(payload, forKey: .start)
        case .approvalResolved(let payload):
            try container.encode(payload, forKey: .approvalResolved)
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
    case resumeAccepted(ClaudeSDKSidecarResumeAccepted)
    case resumeRejected(ClaudeSDKSidecarResumeRejected)
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
        case resumeAccepted
        case resumeRejected
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
        }
    }
}

public protocol ClaudeSDKSidecarTransport: Sendable {
    func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
}

public protocol ClaudeSDKSidecarCommandTransport: ClaudeSDKSidecarTransport {
    func stream(_ command: ClaudeSDKSidecarCommand) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
}

public protocol ClaudeSDKSidecarSessionTransport: Sendable {
    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
    func send(_ command: ClaudeSDKSidecarCommand) async throws
    func cancel() async
}

public enum ClaudeSDKSidecarProcessTransportError: Error, Sendable, Equatable, LocalizedError {
    case missingNewlineTerminator
    case nonZeroExit(code: Int32, stderr: String)
    case invalidJSONLine(String)
    case unsupportedCommand(String)
    case sessionAlreadyStarted
    case sessionNotStarted

    public var errorDescription: String? {
        switch self {
        case .missingNewlineTerminator:
            return "Claude SDK sidecar request JSONL payload is missing a newline terminator."
        case .nonZeroExit(let code, let stderr):
            return "Claude SDK sidecar exited with status \(code): \(stderr)"
        case .invalidJSONLine(let line):
            return "Claude SDK sidecar emitted an invalid JSONL event: \(line)"
        case .unsupportedCommand(let command):
            return "Claude SDK sidecar process transport does not support \(command) commands without a persistent streaming session."
        case .sessionAlreadyStarted:
            return "Claude SDK sidecar persistent process transport session has already started."
        case .sessionNotStarted:
            return "Claude SDK sidecar persistent process transport session has not started."
        }
    }
}

private final class ClaudeSDKSidecarLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            if !lineData.isEmpty {
                lines.append(lineData)
            }
        }
        return lines
    }
}

public final class ClaudeSDKSidecarPersistentProcessTransport: ClaudeSDKSidecarSessionTransport, @unchecked Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectoryURL: URL?

    private let stateQueue = DispatchQueue(label: "connor.claude-sidecar.persistent-process-transport")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stderrPipe: Pipe?
    private var streamContinuation: AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>.Continuation?

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

    public func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ClaudeSDKSidecarEvent.self, throwing: Error.self)

        let canStart = withLock {
            guard process == nil else { return false }
            streamContinuation = continuation
            return true
        }
        guard canStart else {
            continuation.finish(throwing: ClaudeSDKSidecarProcessTransportError.sessionAlreadyStarted)
            return stream
        }

        do {
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

            withLock {
                self.process = process
                self.stdinHandle = stdin.fileHandleForWriting
                self.stderrPipe = stderr
            }

            try process.run()
            startReading(stdout: stdout, stderr: stderr, continuation: continuation, process: process)
            try await send(.start(request))
        } catch {
            continuation.finish(throwing: error)
        }

        return stream
    }

    public func send(_ command: ClaudeSDKSidecarCommand) async throws {
        let handle: FileHandle? = withLock { stdinHandle }
        guard let handle else {
            throw ClaudeSDKSidecarProcessTransportError.sessionNotStarted
        }
        var data = try JSONEncoder().encode(command)
        data.append(0x0A)
        guard data.last == 0x0A else {
            throw ClaudeSDKSidecarProcessTransportError.missingNewlineTerminator
        }
        try handle.write(contentsOf: data)
    }

    public func cancel() async {
        let resources = withLock {
            let resources = (process, stdinHandle, streamContinuation)
            process = nil
            stdinHandle = nil
            streamContinuation = nil
            stderrPipe = nil
            return resources
        }
        try? resources.1?.close()
        if resources.0?.isRunning == true {
            resources.0?.terminate()
        }
        resources.2?.finish()
    }

    private func startReading(
        stdout: Pipe,
        stderr: Pipe,
        continuation: AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>.Continuation,
        process: Process
    ) {
        let decoder = JSONDecoder()
        let lineBuffer = ClaudeSDKSidecarLineBuffer()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for lineData in lineBuffer.append(data) {
                do {
                    continuation.yield(try decoder.decode(ClaudeSDKSidecarEvent.self, from: lineData))
                } catch {
                    let lineText = String(data: lineData, encoding: .utf8) ?? ""
                    continuation.finish(throwing: ClaudeSDKSidecarProcessTransportError.invalidJSONLine(lineText))
                }
            }
        }

        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 && process.terminationReason != .uncaughtSignal {
                continuation.finish(throwing: ClaudeSDKSidecarProcessTransportError.nonZeroExit(
                    code: process.terminationStatus,
                    stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            } else {
                continuation.finish()
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        stateQueue.sync(execute: body)
    }
}

public struct ClaudeSDKSidecarProcessTransport: ClaudeSDKSidecarCommandTransport {
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
        await stream(.start(request))
    }

    public func stream(_ command: ClaudeSDKSidecarCommand) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        let executableURL = executableURL
        let arguments = arguments
        let environment = environment
        let currentDirectoryURL = currentDirectoryURL

        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    guard case .start(let request) = command else {
                        throw ClaudeSDKSidecarProcessTransportError.unsupportedCommand(command.commandName)
                    }
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

private extension ClaudeSDKSidecarEvent {
    var isTerminalForConnorSubmit: Bool {
        switch self {
        case .runCompleted, .runFailed:
            return true
        default:
            return false
        }
    }
}

public struct ClaudeSDKSidecarSessionBackend<Transport: ClaudeSDKSidecarSessionTransport>: AgentBackend {
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
                let sidecarEvents = await transport.start(sidecarRequest)
                for try await event in sidecarEvents {
                    if let mapped = ClaudeSDKSidecarEventMapper.map(event, request: request) {
                        continuation.yield(mapped)
                    }
                    if event.isTerminalForConnorSubmit {
                        await transport.cancel()
                        break
                    }
                }
                continuation.finish()
            }
        }
    }

    public func abort(runID: String) async {
        await transport.cancel()
    }
}

private enum ClaudeSDKSidecarEventMapper {
    static func map(_ event: ClaudeSDKSidecarEvent, request: AgentChatRequest) -> AgentEvent? {
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
        case .resumeAccepted, .resumeRejected:
            return nil
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
                    if let mapped = ClaudeSDKSidecarEventMapper.map(event, request: request) {
                        continuation.yield(mapped)
                    }
                }
                continuation.finish()
            }
        }
    }

}
