import Foundation
import ConnorGraphAgent
import ConnorGraphCore


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
    case timedOut(seconds: TimeInterval)

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
        case .timedOut(let seconds):
            return "Claude SDK sidecar timed out after \(seconds) seconds."
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
    private var activeRequest: ClaudeSDKSidecarRequest?

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
                self.activeRequest = request
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
            let resources = (process, stdinHandle, streamContinuation, activeRequest)
            process = nil
            stdinHandle = nil
            streamContinuation = nil
            stderrPipe = nil
            activeRequest = nil
            return resources
        }
        if let request = resources.3 {
            var data = try? JSONEncoder().encode(ClaudeSDKSidecarCommand.cancel(ClaudeSDKSidecarCancelCommand(
                connorRunID: request.connorRunID,
                connorSessionID: request.connorSessionID,
                reason: "cancelled by Connor"
            )))
            data?.append(0x0A)
            if let data { try? resources.1?.write(contentsOf: data) }
            try? await Task.sleep(nanoseconds: 100_000_000)
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
            self.withLock {
                if self.process === process {
                    self.process = nil
                    self.stdinHandle = nil
                    self.streamContinuation = nil
                    self.stderrPipe = nil
                    self.activeRequest = nil
                }
            }
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
    public var processTimeout: TimeInterval

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil,
        processTimeout: TimeInterval = 300
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.processTimeout = processTimeout
    }

    public func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        await stream(.start(request))
    }

    public func stream(_ command: ClaudeSDKSidecarCommand) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        let executableURL = executableURL
        let arguments = arguments
        let environment = environment
        let currentDirectoryURL = currentDirectoryURL
        let processTimeout = processTimeout

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
                        currentDirectoryURL: currentDirectoryURL,
                        processTimeout: processTimeout
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
    currentDirectoryURL: URL?,
    processTimeout: TimeInterval
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

    let terminationSemaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminationSemaphore.signal() }

    try process.run()
    stdin.fileHandleForWriting.write(requestData)
    try? stdin.fileHandleForWriting.close()

    let waitResult = terminationSemaphore.wait(timeout: .now() + processTimeout)
    if waitResult == .timedOut {
        if process.isRunning {
            process.terminate()
            _ = terminationSemaphore.wait(timeout: .now() + 1)
        }
        throw ClaudeSDKSidecarProcessTransportError.timedOut(seconds: processTimeout)
    }

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

extension ClaudeSDKSidecarEvent {
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
    public var thinkingLevel: AppLLMThinkingLevel

    public init(transport: Transport, workingDirectory: URL, thinkingLevel: AppLLMThinkingLevel = .defaultLevel) {
        self.transport = transport
        self.workingDirectory = workingDirectory
        self.thinkingLevel = thinkingLevel
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let sidecarRequest = ClaudeSDKSidecarRequest(request: request, workingDirectory: workingDirectory, effort: thinkingLevel.effortValue)
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

    public func abort(runID: String) {
        Task { await transport.cancel() }
    }
}

enum ClaudeSDKSidecarEventMapper {
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
        case .sidecarHealth, .runtimeDiagnostic, .heartbeat:
            return nil
        }
    }
}

public struct ClaudeSDKSidecarBackend<Transport: ClaudeSDKSidecarTransport>: AgentBackend {
    public var transport: Transport
    public var workingDirectory: URL
    public var instructionAppendix: String
    public var thinkingLevel: AppLLMThinkingLevel

    public init(transport: Transport, workingDirectory: URL, instructionAppendix: String = "", thinkingLevel: AppLLMThinkingLevel = .defaultLevel) {
        self.transport = transport
        self.workingDirectory = workingDirectory
        self.instructionAppendix = instructionAppendix
        self.thinkingLevel = thinkingLevel
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let sidecarRequest = ClaudeSDKSidecarRequest(request: request, workingDirectory: workingDirectory, instructionAppendix: instructionAppendix, effort: thinkingLevel.effortValue)
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
