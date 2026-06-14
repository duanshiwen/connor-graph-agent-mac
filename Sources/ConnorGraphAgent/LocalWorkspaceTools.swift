import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

public struct LocalReadFileTool: AgentTool {
    public let name = "Read"
    public let description = "Read a text file from the configured local workspace. Supports 1-based line offset and limit. Paths must stay inside allowed workspace roots."
    public let permission: AgentPermissionCapability = .readWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "file_path": .string(description: "Path to a file inside the workspace."),
        "offset": .integer(description: "Optional 1-based line number to start reading from."),
        "limit": .integer(description: "Optional maximum number of lines to return.")
    ], required: ["file_path"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("file_path") else {
            throw AgentToolError.invalidArguments("file_path is required")
        }
        let path = try policy.resolvePath(rawPath)
        try policy.validateReadablePath(path)
        try policy.validateReadableSize(path: path)
        let text = try String(contentsOf: path, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let offset = max(arguments.int("offset") ?? 1, 1)
        let limit = max(arguments.int("limit") ?? min(lines.count, 2000), 0)
        let start = min(offset - 1, lines.count)
        let end = min(start + limit, lines.count)
        let selected = lines[start..<end].enumerated().map { index, line in
            "\(start + index + 1): \(line)"
        }.joined(separator: "\n")
        let truncated = start > 0 || end < lines.count
        let json = LocalToolJSON.encode([
            "path": path.path,
            "lineCount": lines.count,
            "offset": offset,
            "limit": limit,
            "truncated": truncated
        ])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: selected, contentJSON: json)
    }
}

public struct LocalListDirectoryTool: AgentTool {
    public let name = "LS"
    public let description = "List directory contents inside the configured local workspace. Directories end with '/'."
    public let permission: AgentPermissionCapability = .listWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "path": .string(description: "Directory path inside the workspace. Defaults to '.'.")
    ], required: [])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let rawPath = arguments.string("path") ?? "."
        let path = try policy.resolvePath(rawPath)
        try policy.validateSearchScope(path)
        let entries = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])
            .map { url -> String in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return url.lastPathComponent + ((values?.isDirectory == true) ? "/" : "")
            }
            .sorted()
        let truncated = entries.count > policy.maxSearchResults
        let shown = entries.prefix(policy.maxSearchResults).joined(separator: "\n")
        let json = LocalToolJSON.encode(["path": path.path, "count": entries.count, "truncated": truncated])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: shown, contentJSON: json)
    }
}

public struct LocalGlobTool: AgentTool {
    public let name = "Glob"
    public let description = "Find files matching a glob pattern inside the configured local workspace."
    public let permission: AgentPermissionCapability = .listWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "pattern": .string(description: "Glob pattern, for example '**/*.swift'."),
        "path": .string(description: "Directory to search from. Defaults to '.'.")
    ], required: ["pattern"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let pattern = arguments.string("pattern"), !pattern.isEmpty else {
            throw AgentToolError.invalidArguments("pattern is required")
        }
        let root = try policy.resolvePath(arguments.string("path") ?? ".")
        try policy.validateSearchScope(root)
        let matches = try LocalWorkspaceScanner.files(under: root, relativeTo: policy.workingDirectory)
            .filter { LocalWorkspaceScanner.globMatch(pattern: pattern, path: $0) }
            .sorted()
        let truncated = matches.count > policy.maxSearchResults
        let shown = matches.prefix(policy.maxSearchResults).joined(separator: "\n")
        let json = LocalToolJSON.encode(["pattern": pattern, "count": matches.count, "truncated": truncated])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: shown, contentJSON: json)
    }
}

public struct LocalGrepTool: AgentTool {
    public let name = "Grep"
    public let description = "Search text files inside the configured local workspace using literal or regular expression patterns."
    public let permission: AgentPermissionCapability = .searchWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "pattern": .string(description: "Text or regex pattern to search for."),
        "path": .string(description: "Directory to search from. Defaults to '.'."),
        "glob": .string(description: "Optional file glob filter, for example '*.swift'."),
        "ignore_case": .boolean(description: "Whether to search case-insensitively."),
        "literal": .boolean(description: "Whether to treat pattern as literal text."),
        "context": .integer(description: "Number of context lines before and after each match.")
    ], required: ["pattern"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let pattern = arguments.string("pattern"), !pattern.isEmpty else {
            throw AgentToolError.invalidArguments("pattern is required")
        }
        let root = try policy.resolvePath(arguments.string("path") ?? ".")
        try policy.validateSearchScope(root)
        let glob = arguments.string("glob")
        let literal = arguments.bool("literal") ?? false
        let ignoreCase = arguments.bool("ignore_case") ?? false
        let contextLines = max(arguments.int("context") ?? 0, 0)
        let files = try LocalWorkspaceScanner.files(under: root, relativeTo: policy.workingDirectory)
            .filter { relative in glob.map { LocalWorkspaceScanner.globMatch(pattern: $0, path: relative) } ?? true }
            .sorted()

        var rows: [String] = []
        var matchCount = 0
        let regex: NSRegularExpression?
        if literal {
            regex = nil
        } else {
            regex = try NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        }
        let needle = ignoreCase ? pattern.lowercased() : pattern

        fileLoop: for relative in files {
            let absolute = policy.workingDirectory.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: absolute, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for index in lines.indices {
                let line = lines[index]
                let haystack = ignoreCase ? line.lowercased() : line
                let matched: Bool
                if literal {
                    matched = haystack.contains(needle)
                } else if let regex {
                    let range = NSRange(location: 0, length: (line as NSString).length)
                    matched = regex.firstMatch(in: line, range: range) != nil
                } else {
                    matched = false
                }
                guard matched else { continue }
                let lower = max(0, index - contextLines)
                let upper = min(lines.count - 1, index + contextLines)
                for contextIndex in lower...upper {
                    let marker = contextIndex == index ? ":" : "-"
                    rows.append("\(relative):\(contextIndex + 1)\(marker) \(lines[contextIndex])")
                }
                matchCount += 1
                if matchCount >= policy.maxSearchResults { break fileLoop }
            }
        }
        let truncated = matchCount >= policy.maxSearchResults
        let json = LocalToolJSON.encode(["matches": matchCount, "truncated": truncated])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: rows.joined(separator: "\n"), contentJSON: json)
    }
}

public struct LocalBashTool: AgentTool {
    public let name = "Bash"
    public let description = "Execute a non-interactive shell command in the configured local workspace with policy classification, timeout, stdout/stderr capture, and output truncation."
    public let permission: AgentPermissionCapability = .runReadOnlyShellCommand
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "command": .string(description: "Shell command to execute."),
        "timeout_seconds": .integer(description: "Optional timeout in seconds. Defaults to 30, max 120."),
        "working_directory": .string(description: "Optional workspace-relative directory to run in.")
    ], required: ["command"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let command = arguments.string("command"), !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("command is required")
        }
        let classification = policy.classifyCommand(command)
        if classification.risk == .destructive {
            throw LocalWorkspacePolicyError.commandDenied(classification.reason)
        }
        let requiredCapability = Self.capability(for: classification.risk)
        let permissionPayloadJSON = LocalToolJSON.encode(["command": command, "classification": classification.risk.rawValue]) ?? "{}"
        if !context.approvedCapabilities.contains(requiredCapability) {
            let permissionDecision = await context.policyEngine.evaluate(
                capability: requiredCapability,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: name,
                payloadJSON: permissionPayloadJSON
            )
            switch permissionDecision.outcome {
            case .approved:
                break
            case .needsApproval:
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: permissionDecision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: requiredCapability,
                    toolName: name,
                    payloadJSON: permissionPayloadJSON
                ))
            case .denied:
                throw AgentToolError.permissionDenied(permissionDecision.reason)
            }
        }
        let workingDirectory = try policy.resolvePath(arguments.string("working_directory") ?? ".")
        try policy.validateSearchScope(workingDirectory)
        let timeout = min(max(arguments.int("timeout_seconds") ?? 30, 1), 120)
        let execution = try await LocalShellExecutor.run(command: command, workingDirectory: workingDirectory, timeoutSeconds: timeout, maxOutputBytes: policy.maxToolOutputBytes)
        let json = LocalToolJSON.encode([
            "command": command,
            "classification": classification.risk.rawValue,
            "exitCode": execution.exitCode,
            "timedOut": execution.timedOut,
            "truncated": execution.truncated
        ])
        let text = "exitCode: \(execution.exitCode)\nstdout:\n\(execution.stdout)\n\nstderr:\n\(execution.stderr)"
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text, contentJSON: json, error: execution.exitCode == 0 ? nil : "Command exited with code \(execution.exitCode)")
    }

    private static func capability(for risk: ShellCommandRisk) -> AgentPermissionCapability {
        switch risk {
        case .readOnly: return .runReadOnlyShellCommand
        case .workspaceWrite: return .runWorkspaceShellCommand
        case .network: return .runNetworkShellCommand
        case .destructive: return .runDestructiveShellCommand
        case .unknown: return .runWorkspaceShellCommand
        }
    }
}

public struct LocalWriteFileTool: AgentTool {
    public let name = "Write"
    public let description = "Create or overwrite a text file inside the configured local workspace. Protected paths are denied."
    public let permission: AgentPermissionCapability = .writeWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "file_path": .string(description: "Path to write inside the workspace."),
        "content": .string(description: "Complete file content to write.")
    ], required: ["file_path", "content"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("file_path"), let content = arguments.string("content") else {
            throw AgentToolError.invalidArguments("file_path and content are required")
        }
        let path = try policy.resolvePath(rawPath)
        let existed = FileManager.default.fileExists(atPath: path.path)
        try policy.validateWritablePath(path, operation: existed ? .overwriteFile : .createFile)
        try policy.validateWritableSize(path: path, content: content)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: path, atomically: true, encoding: .utf8)
        let json = LocalToolJSON.encode([
            "path": path.path,
            "operation": existed ? "overwritten" : "created",
            "bytesWritten": content.utf8.count,
            "afterHash": LocalFileHash.sha256(content)
        ])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "File \(existed ? "overwritten" : "created"): \(path.path)", contentJSON: json)
    }
}

public struct LocalEditFileTool: AgentTool {
    public let name = "Edit"
    public let description = "Replace a unique old_text occurrence in a text file inside the configured local workspace. Fails if old_text is missing or not unique."
    public let permission: AgentPermissionCapability = .editWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "file_path": .string(description: "Path to edit inside the workspace."),
        "old_text": .string(description: "Exact text to replace. Must occur exactly once."),
        "new_text": .string(description: "Replacement text.")
    ], required: ["file_path", "old_text", "new_text"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("file_path"), let oldText = arguments.string("old_text"), let newText = arguments.string("new_text") else {
            throw AgentToolError.invalidArguments("file_path, old_text, and new_text are required")
        }
        let path = try policy.resolvePath(rawPath)
        try policy.validateReadablePath(path)
        try policy.validateWritablePath(path, operation: .editFile)
        let original = try String(contentsOf: path, encoding: .utf8)
        let updated = try LocalTextEditor.replacingUnique(original: original, oldText: oldText, newText: newText)
        try policy.validateWritableSize(path: path, content: updated)
        try updated.write(to: path, atomically: true, encoding: .utf8)
        let json = LocalToolJSON.encode([
            "path": path.path,
            "beforeHash": LocalFileHash.sha256(original),
            "afterHash": LocalFileHash.sha256(updated),
            "edits": 1
        ])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Edited file: \(path.path)", contentJSON: json)
    }
}

public struct LocalMultiEditTool: AgentTool {
    public let name = "MultiEdit"
    public let description = "Apply multiple exact text replacements atomically to one workspace file. Every old_text must occur exactly once in the original file."
    public let permission: AgentPermissionCapability = .editWorkspaceFile
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "file_path": .string(description: "Path to edit inside the workspace."),
        "edits": .array(
            items: .object(properties: [
                "old_text": .string(description: "Exact text to replace. Must occur exactly once in the original file."),
                "new_text": .string(description: "Replacement text.")
            ], required: ["old_text", "new_text"]),
            description: "Ordered list of exact replacements to validate against the original file and then apply atomically."
        )
    ], required: ["file_path", "edits"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("file_path"), let rawEdits = arguments.array("edits") else {
            throw AgentToolError.invalidArguments("file_path and edits are required")
        }
        let edits: [(oldText: String, newText: String)] = try rawEdits.map { value in
            guard let object = value.objectValue,
                  let oldText = object["old_text"]?.stringValue,
                  let newText = object["new_text"]?.stringValue else {
                throw AgentToolError.invalidArguments("Each edit requires old_text and new_text")
            }
            return (oldText, newText)
        }
        guard !edits.isEmpty else { throw AgentToolError.invalidArguments("edits must not be empty") }
        let path = try policy.resolvePath(rawPath)
        try policy.validateReadablePath(path)
        try policy.validateWritablePath(path, operation: .editFile)
        let original = try String(contentsOf: path, encoding: .utf8)
        let updated = try LocalTextEditor.applyingAtomicEdits(original: original, edits: edits)
        try policy.validateWritableSize(path: path, content: updated)
        try updated.write(to: path, atomically: true, encoding: .utf8)
        let json = LocalToolJSON.encode([
            "path": path.path,
            "beforeHash": LocalFileHash.sha256(original),
            "afterHash": LocalFileHash.sha256(updated),
            "edits": edits.count
        ])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Applied \(edits.count) edits to file: \(path.path)", contentJSON: json)
    }
}

enum LocalTextEditor {
    static func replacingUnique(original: String, oldText: String, newText: String) throws -> String {
        guard !oldText.isEmpty else { throw AgentToolError.invalidArguments("old_text must not be empty") }
        let ranges = ranges(of: oldText, in: original)
        guard ranges.count == 1 else {
            throw AgentToolError.invalidArguments("old_text must occur exactly once; found \(ranges.count)")
        }
        return original.replacingCharacters(in: ranges[0], with: newText)
    }

    static func applyingAtomicEdits(original: String, edits: [(oldText: String, newText: String)]) throws -> String {
        for edit in edits {
            let ranges = ranges(of: edit.oldText, in: original)
            guard ranges.count == 1 else {
                throw AgentToolError.invalidArguments("old_text must occur exactly once; found \(ranges.count): \(edit.oldText)")
            }
        }
        var updated = original
        for edit in edits {
            updated = try replacingUnique(original: updated, oldText: edit.oldText, newText: edit.newText)
        }
        return updated
    }

    private static func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex, let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}

enum LocalFileHash {
    static func sha256(_ text: String) -> String {
        // FNV-1a 64-bit is sufficient here as a stable lightweight audit fingerprint without adding CryptoKit platform constraints.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

struct LocalShellExecution: Sendable, Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var timedOut: Bool
    var truncated: Bool
}

enum LocalShellExecutor {
    static func run(command: String, workingDirectory: URL, timeoutSeconds: Int, maxOutputBytes: Int) async throws -> LocalShellExecution {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw LocalWorkspacePolicyError.commandTimedOut(command)
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let truncatedStdout = truncate(stdout, maxBytes: maxOutputBytes)
        let truncatedStderr = truncate(stderr, maxBytes: maxOutputBytes)
        return LocalShellExecution(
            stdout: truncatedStdout.text,
            stderr: truncatedStderr.text,
            exitCode: process.terminationStatus,
            timedOut: false,
            truncated: truncatedStdout.truncated || truncatedStderr.truncated
        )
    }

    private static func truncate(_ text: String, maxBytes: Int) -> (text: String, truncated: Bool) {
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return (text, false) }
        let prefix = Data(bytes.prefix(maxBytes))
        let truncated = String(data: prefix, encoding: .utf8) ?? String(decoding: bytes.prefix(maxBytes), as: UTF8.self)
        return (truncated + "\n[truncated to \(maxBytes) bytes]", true)
    }
}

enum LocalWorkspaceScanner {
    static func files(under root: URL, relativeTo base: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var results: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                let name = url.lastPathComponent
                if [".git", "node_modules", ".build", "DerivedData"].contains(name) {
                    enumerator.skipDescendants()
                }
            }
            guard values?.isRegularFile == true else { continue }
            results.append(relativePath(from: base, to: url))
        }
        return results
    }

    static func relativePath(from base: URL, to url: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == basePath { return "." }
        if path.hasPrefix(basePath + "/") { return String(path.dropFirst(basePath.count + 1)) }
        return path
    }

    static func globMatch(pattern: String, path: String) -> Bool {
        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            return fnmatch(pattern, path, 0) == 0 || fnmatch(suffix, path, 0) == 0
        }
        return fnmatch(pattern, path, 0) == 0
    }
}

enum LocalToolJSON {
    static func encode(_ dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
