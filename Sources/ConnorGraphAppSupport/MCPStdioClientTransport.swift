import Foundation

public enum MCPStdioClientTransportError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingExecutable(String)
    case processNotStarted
    case processTerminated(String)
    case missingContentLength
    case invalidHeader(String)
    case invalidUTF8Frame
    case responseIDMismatch(expected: MCPJSONRPCID, actual: MCPJSONRPCID?)

    public var description: String {
        switch self {
        case .missingExecutable(let command): "missingExecutable: \(command)"
        case .processNotStarted: "processNotStarted"
        case .processTerminated(let stderr): "processTerminated: \(stderr)"
        case .missingContentLength: "missingContentLength"
        case .invalidHeader(let header): "invalidHeader: \(header)"
        case .invalidUTF8Frame: "invalidUTF8Frame"
        case .responseIDMismatch(let expected, let actual): "responseIDMismatch: expected \(expected), actual \(String(describing: actual))"
        }
    }
}

/// Real MCP stdio transport using JSON-RPC messages framed with `Content-Length` headers.
///
/// This transport intentionally owns subprocess lifecycle and filters sensitive inherited
/// environment variables before injecting source-specific variables. It is serial-call
/// oriented; `MCPJSONRPCClient` is an actor and sends requests one at a time today.
public final class MCPStdioClientTransport: MCPClientTransport, @unchecked Sendable {
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectoryURL: URL?

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
        currentDirectoryURL: URL? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }

    public func send(_ message: MCPJSONRPCMessage) async throws -> MCPJSONRPCMessage? {
        try startIfNeeded()
        guard let stdinHandle else { throw MCPStdioClientTransportError.processNotStarted }
        let data = try encoder.encode(message)
        let frameHeader = "Content-Length: \(data.count)\r\n\r\n"
        var frame = Data(frameHeader.utf8)
        frame.append(data)
        try stdinHandle.write(contentsOf: frame)

        guard let id = message.id else { return nil }
        while true {
            guard let response = try readFrame() else { return nil }
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

    private func readFrame() throws -> MCPJSONRPCMessage? {
        guard let stdoutHandle else { throw MCPStdioClientTransportError.processNotStarted }
        var headerData = Data()
        while !headerData.ends(with: Data("\r\n\r\n".utf8)) {
            guard let byte = try stdoutHandle.read(upToCount: 1), !byte.isEmpty else {
                let stderr = stderrText()
                if locked({ process?.isRunning == false }) {
                    throw MCPStdioClientTransportError.processTerminated(stderr)
                }
                return nil
            }
            headerData.append(byte)
        }
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw MCPStdioClientTransportError.invalidHeader("<non-utf8>")
        }
        let lines = headerText.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        var contentLength: Int?
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { throw MCPStdioClientTransportError.invalidHeader(line) }
            if parts[0].localizedCaseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(parts[1])
            }
        }
        guard let contentLength else { throw MCPStdioClientTransportError.missingContentLength }
        guard let payload = try stdoutHandle.read(upToCount: contentLength), payload.count == contentLength else {
            let stderr = stderrText()
            throw MCPStdioClientTransportError.processTerminated(stderr)
        }
        return try decoder.decode(MCPJSONRPCMessage.self, from: payload)
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

private extension Data {
    func ends(with suffix: Data) -> Bool {
        guard count >= suffix.count else { return false }
        return self.suffix(suffix.count) == suffix
    }
}
