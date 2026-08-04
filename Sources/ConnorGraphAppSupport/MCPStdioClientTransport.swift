import Foundation

public enum MCPStdioClientTransportError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingExecutable(String)
    case processNotStarted
    case processTerminated(String)
    case missingContentLength
    case invalidHeader(String)
    case invalidUTF8Frame
    case responseTooLarge(Int)
    case requestTimedOut(TimeInterval)
    case responseIDMismatch(expected: MCPJSONRPCID, actual: MCPJSONRPCID?)

    public var description: String {
        switch self {
        case .missingExecutable(let command): "missingExecutable: \(command)"
        case .processNotStarted: "processNotStarted"
        case .processTerminated(let stderr): "processTerminated: \(stderr)"
        case .missingContentLength: "missingContentLength"
        case .invalidHeader(let header): "invalidHeader: \(header)"
        case .invalidUTF8Frame: "invalidUTF8Frame"
        case .responseTooLarge(let maximumBytes): "responseTooLarge: maximum \(maximumBytes) bytes"
        case .requestTimedOut(let seconds): "requestTimedOut: \(seconds) seconds"
        case .responseIDMismatch(let expected, let actual): "responseIDMismatch: expected \(expected), actual \(String(describing: actual))"
        }
    }
}

/// Real MCP stdio transport using newline-delimited JSON-RPC messages.
///
/// This transport intentionally owns subprocess lifecycle and filters sensitive inherited
/// environment variables before injecting source-specific variables. It is serial-call
/// oriented; `MCPJSONRPCClient` is an actor and sends requests one at a time today.
public final class MCPStdioClientTransport: MCPClientTransport, @unchecked Sendable {
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectoryURL: URL?
    public var requestTimeout: TimeInterval
    public var maximumResponseBytes: Int

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrPipe: Pipe?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil,
        requestTimeout: TimeInterval = 30,
        maximumResponseBytes: Int = 10 * 1024 * 1024
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.requestTimeout = requestTimeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    public func send(_ message: MCPJSONRPCMessage) async throws -> MCPJSONRPCMessage? {
        try startIfNeeded()
        guard let stdinHandle else { throw MCPStdioClientTransportError.processNotStarted }
        var data = try encoder.encode(message)
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)

        guard let id = message.id else { return nil }
        return try await response(matching: id)
    }

    private func response(matching id: MCPJSONRPCID) async throws -> MCPJSONRPCMessage? {
        let timeout = max(0.1, requestTimeout)
        return try await withThrowingTaskGroup(of: MCPJSONRPCMessage?.self) { group in
            // The blocking pipe read runs in a detached task so the timeout can abandon
            // it: awaiting a cancelled task handle returns immediately instead of waiting
            // for the underlying blocking read to finish (e.g. a server that never replies).
            let readTask = Task.detached(priority: .userInitiated) {
                try self.readResponse(matching: id)
            }
            group.addTask { try await readTask.value }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                try await self.close()
                throw MCPStdioClientTransportError.requestTimedOut(timeout)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func readResponse(matching id: MCPJSONRPCID) throws -> MCPJSONRPCMessage? {
        while true {
            guard let response = try readLine() else { return nil }
            if response.id == id { return response }
            if response.id != nil {
                throw MCPStdioClientTransportError.responseIDMismatch(expected: id, actual: response.id)
            }
            // Server notifications are allowed while waiting for a response. Ignore for now.
        }
    }

    public func close() async throws {
        let resources = locked {
            let resources = (process, stdinHandle, stdoutHandle, stderrPipe)
            process = nil
            stdinHandle = nil
            stdoutHandle = nil
            stderrPipe = nil
            return resources
        }
        try? resources.1?.close()
        try? resources.2?.close()
        if resources.0?.isRunning == true {
            resources.0?.terminate()
        }
    }

    private func startIfNeeded() throws {
        if locked({ self.process != nil }) { return }
        let executableURL = try resolveExecutableURL(command)
        let subprocess = Process()
        subprocess.executableURL = executableURL
        subprocess.arguments = arguments
        subprocess.currentDirectoryURL = currentDirectoryURL
        subprocess.environment = Self.filteredEnvironment(overrides: environment)

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        subprocess.standardInput = stdin
        subprocess.standardOutput = stdout
        subprocess.standardError = stderr

        try subprocess.run()
        locked {
            self.process = subprocess
            self.stdinHandle = stdin.fileHandleForWriting
            self.stdoutHandle = stdout.fileHandleForReading
            self.stderrPipe = stderr
        }
    }

    private func resolveExecutableURL(_ command: String) throws -> URL {
        if command.contains("/") {
            let url = URL(fileURLWithPath: command)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw MCPStdioClientTransportError.missingExecutable(command)
            }
            return url
        }
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        for path in searchPaths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw MCPStdioClientTransportError.missingExecutable(command)
    }

    private func readLine() throws -> MCPJSONRPCMessage? {
        guard let stdoutHandle else { throw MCPStdioClientTransportError.processNotStarted }
        var line = Data()
        while true {
            guard let byte = try stdoutHandle.read(upToCount: 1), !byte.isEmpty else {
                let stderr = stderrText()
                if locked({ process?.isRunning == false }) {
                    throw MCPStdioClientTransportError.processTerminated(stderr)
                }
                return nil
            }
            if byte[byte.startIndex] == 0x0A { break }
            line.append(byte)
            if line.count > maximumResponseBytes {
                throw MCPStdioClientTransportError.responseTooLarge(maximumResponseBytes)
            }
        }
        if line.last == 0x0D { line.removeLast() }
        guard !line.isEmpty else { return try readLine() }
        return try decoder.decode(MCPJSONRPCMessage.self, from: line)
    }

    private func stderrText() -> String {
        guard let stderrPipe else { return "" }
        let data = stderrPipe.fileHandleForReading.availableData
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public static func filteredEnvironment(overrides: [String: String] = [:]) -> [String: String] {
        let blocked: Set<String> = [
            "ANTHROPIC_API_KEY",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "CLAUDE_CODE_OAUTH_REFRESH_TOKEN",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_SESSION_TOKEN",
            "GITHUB_TOKEN",
            "GH_TOKEN",
            "OPENAI_API_KEY",
            "GOOGLE_API_KEY",
            "STRIPE_SECRET_KEY",
            "NPM_TOKEN"
        ]
        var environment = ProcessInfo.processInfo.environment.filter { !blocked.contains($0.key) }
        overrides.forEach { key, value in environment[key] = value }
        return environment
    }
}
