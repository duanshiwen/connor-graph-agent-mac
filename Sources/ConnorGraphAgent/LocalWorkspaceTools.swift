import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

public struct LocalReadFileTool: AgentTool {
    public let name = "Read"
    public let description = "Read a text file from the configured local workspace. A small file is returned completely in a single call. A larger file is read from the start (or from the given 1-based offset) and automatically truncated to the output budget, returning nextOffset when more lines remain so you can continue with Read(filePath, offset: nextOffset). Optional offset/limit only create an explicit window on large files; do not pass a small limit for a small file. Paths must stay inside allowed workspace roots."
    public let permission: AgentPermissionCapability = .readWorkspaceFile
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "filePath": .string(description: "Path to a file inside the workspace."),
        "offset": .integer(description: "Optional 1-based line number to start reading from. Defaults to 1; use it to continue from a returned nextOffset."),
        "limit": .integer(description: "Optional maximum number of lines for an explicit window on large files. Omit it to read as much as fits the output budget (a small file is then returned in full).")
    ], required: ["filePath"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("filePath") ?? arguments.string("file_path") ?? arguments.string("path") else {
            throw AgentToolError.invalidArguments("filePath is required")
        }
        let path = try policy.resolvePath(rawPath)
        try policy.validateReadablePath(path)
        try policy.validateReadableSize(path: path)
        let text = try String(contentsOf: path, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxBytes = max(policy.maxToolOutputBytes, 1)
        let allFormatted = lines.enumerated().map { "\($0.offset + 1): \($0.element)" }
        let fullText = allFormatted.joined(separator: "\n")

        // 小文件整读：整个文件（含行号前缀）能放进单次输出预算时直接返回全文，
        // 即使调用方传了很小的 limit 也不截断——避免“读小文件被压缩/截断”。
        if fullText.utf8.count <= maxBytes {
            let jsonObject: [String: Any] = [
                "path": path.path,
                "lineCount": lines.count,
                "offset": 1,
                "limit": lines.count,
                "truncated": false
            ]
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: fullText, contentJSON: LocalToolJSON.encode(jsonObject))
        }

        // 大文件自动分页：默认按输出预算自动截断并返回 nextOffset；
        // 显式 offset/limit 仍可覆盖窗口（offset 用于从 nextOffset 继续）。
        let offset = max(arguments.int("offset") ?? 1, 1)
        let start = min(offset - 1, lines.count)
        let requestedLimit = arguments.int("limit")
        var end = start
        var usedBytes = 0
        while end < lines.count {
            if let requestedLimit, end - start >= requestedLimit { break }
            let lineBytes = allFormatted[end].utf8.count + 1
            if end > start, usedBytes + lineBytes > maxBytes { break }
            usedBytes += lineBytes
            end += 1
        }
        let selected = allFormatted[start..<end].joined(separator: "\n")
        let truncated = end < lines.count
        var jsonObject: [String: Any] = [
            "path": path.path,
            "lineCount": lines.count,
            "offset": offset,
            "limit": end - start,
            "truncated": truncated
        ]
        if truncated { jsonObject["nextOffset"] = end + 1 }
        let json = LocalToolJSON.encode(jsonObject)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: selected, contentJSON: json)
    }
}

public struct LocalListDirectoryTool: AgentTool {
    public let name = "LS"
    public let description = "List directory contents inside the configured local workspace. Directories end with '/'. Large directories are paginated with offset and limit; when the result is truncated it returns nextOffset so you can continue."
    public let permission: AgentPermissionCapability = .listWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "path": .string(description: "Directory path inside the workspace. Defaults to '.'."),
        "offset": .integer(description: "Optional 0-based index of the first entry to return. Defaults to 0."),
        "limit": .integer(description: "Optional maximum number of entries to return. Defaults to the workspace search limit; maximum 1000.")
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
        let offset = max(arguments.int("offset") ?? 0, 0)
        let limit = min(max(arguments.int("limit") ?? policy.maxSearchResults, 0), 1_000)
        let start = min(offset, entries.count)
        let end = min(start + limit, entries.count)
        let shown = entries[start..<end].joined(separator: "\n")
        let truncated = end < entries.count
        let suffix = truncated ? "\n[truncated: showing \(end - start) of \(entries.count) entries; continue with offset=\(end)]" : ""
        var jsonObject: [String: Any] = [
            "path": path.path,
            "count": entries.count,
            "offset": offset,
            "limit": limit,
            "truncated": truncated
        ]
        if truncated { jsonObject["nextOffset"] = end }
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: shown + suffix, contentJSON: LocalToolJSON.encode(jsonObject))
    }
}

public struct LocalGlobTool: AgentTool {
    public let name = "Glob"
    public let description = "Find files matching a glob pattern inside the configured local workspace. Large result sets are paginated with offset and limit; when the result is truncated it returns nextOffset so you can continue."
    public let permission: AgentPermissionCapability = .listWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "pattern": .string(description: "Glob pattern, for example '**/*.swift'."),
        "path": .string(description: "Directory to search from. Defaults to '.'."),
        "offset": .integer(description: "Optional 0-based index of the first match to return. Defaults to 0."),
        "limit": .integer(description: "Optional maximum number of matches to return. Defaults to the workspace search limit; maximum 1000.")
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
        let offset = max(arguments.int("offset") ?? 0, 0)
        let limit = min(max(arguments.int("limit") ?? policy.maxSearchResults, 0), 1_000)
        let start = min(offset, matches.count)
        let end = min(start + limit, matches.count)
        let shown = matches[start..<end].joined(separator: "\n")
        let truncated = end < matches.count
        let suffix = truncated ? "\n[truncated: showing \(end - start) of \(matches.count) matches; continue with offset=\(end)]" : ""
        var jsonObject: [String: Any] = [
            "pattern": pattern,
            "count": matches.count,
            "offset": offset,
            "limit": limit,
            "truncated": truncated
        ]
        if truncated { jsonObject["nextOffset"] = end }
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: shown + suffix, contentJSON: LocalToolJSON.encode(jsonObject))
    }
}

public struct LocalGrepTool: AgentTool {
    public let name = "Grep"
    public let description = "Search text files inside the configured local workspace using literal or regular expression patterns. Matches are paginated with offset and limit; when the result is truncated it returns nextOffset so you can continue."
    public let permission: AgentPermissionCapability = .searchWorkspaceFiles
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "pattern": .string(description: "Text or regex pattern to search for."),
        "path": .string(description: "Directory to search from. Defaults to '.'."),
        "glob": .string(description: "Optional file glob filter, for example '*.swift'."),
        "ignoreCase": .boolean(description: "Whether to search case-insensitively."),
        "literal": .boolean(description: "Whether to treat pattern as literal text."),
        "context": .integer(description: "Number of context lines before and after each match."),
        "offset": .integer(description: "Optional 0-based index of the first match to return. Defaults to 0."),
        "limit": .integer(description: "Optional maximum number of matches to return. Defaults to the workspace search limit; maximum 1000.")
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
        let ignoreCase = arguments.bool("ignoreCase") ?? arguments.bool("ignore_case") ?? false
        let contextLines = max(arguments.int("context") ?? 0, 0)
        let offset = max(arguments.int("offset") ?? 0, 0)
        let limit = min(max(arguments.int("limit") ?? policy.maxSearchResults, 0), 1_000)
        let windowEnd = offset + limit
        let files = try LocalWorkspaceScanner.files(under: root, relativeTo: policy.workingDirectory)
            .filter { relative in glob.map { LocalWorkspaceScanner.globMatch(pattern: $0, path: relative) } ?? true }
            .sorted()

        var rows: [String] = []
        var seenMatches = 0
        var returnedMatches = 0
        var hasMoreMatches = false
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
                if seenMatches >= windowEnd {
                    hasMoreMatches = true
                    break fileLoop
                }
                if seenMatches >= offset {
                    let lower = max(0, index - contextLines)
                    let upper = min(lines.count - 1, index + contextLines)
                    for contextIndex in lower...upper {
                        let marker = contextIndex == index ? ":" : "-"
                        rows.append("\(relative):\(contextIndex + 1)\(marker) \(lines[contextIndex])")
                    }
                    returnedMatches += 1
                }
                seenMatches += 1
            }
        }
        let truncated = hasMoreMatches
        let suffix = truncated ? "\n[truncated: showing \(returnedMatches) of more matches; continue with offset=\(windowEnd)]" : ""
        var jsonObject: [String: Any] = [
            "matches": returnedMatches,
            "offset": offset,
            "limit": limit,
            "truncated": truncated
        ]
        if truncated { jsonObject["nextOffset"] = windowEnd }
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: rows.joined(separator: "\n") + suffix, contentJSON: LocalToolJSON.encode(jsonObject))
    }
}

public struct LocalShellTool: AgentTool {
    public let name = "Shell"
    public let description = "Execute a focused non-interactive shell command in the configured local workspace. Use it to inspect and search files, query Git, and run builds, tests, formatters, package managers, or scripts. Commands are conservatively classified, sandboxed to allowed workspace roots, timed out, truncated, and audited. Commands that may write, use the network, or have unknown effects require the corresponding approval. Use ApplyPatch for file mutations."
    public let permission: AgentPermissionCapability = .runReadOnlyShellCommand
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "command": .string(description: "Shell command to execute."),
        "timeoutSeconds": .integer(description: "Optional timeout in seconds. Defaults to 30, max 120."),
        "workingDirectory": .string(description: "Optional workspace-relative directory to run in.")
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
        let workingDirectory = try policy.resolvePath(arguments.string("workingDirectory") ?? arguments.string("working_directory") ?? ".")
        try policy.validateSearchScope(workingDirectory)
        let timeout = min(max(arguments.int("timeoutSeconds") ?? arguments.int("timeout_seconds") ?? 30, 1), 120)
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
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "filePath": .string(description: "Path to write inside the workspace."),
        "content": .string(description: "Complete file content to write.")
    ], required: ["filePath", "content"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("filePath") ?? arguments.string("file_path") ?? arguments.string("path"), let content = arguments.string("content") else {
            throw AgentToolError.invalidArguments("filePath and content are required")
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
    public let description = "Replace a unique oldText occurrence in a text file inside the configured local workspace. Fails if oldText is missing or not unique."
    public let permission: AgentPermissionCapability = .editWorkspaceFile
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "filePath": .string(description: "Path to edit inside the workspace."),
        "oldText": .string(description: "Exact text to replace. Must occur exactly once."),
        "newText": .string(description: "Replacement text.")
    ], required: ["filePath", "oldText", "newText"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("filePath") ?? arguments.string("file_path") ?? arguments.string("path"),
              let oldText = arguments.string("oldText") ?? arguments.string("old_text") ?? arguments.string("old_string"),
              let newText = arguments.string("newText") ?? arguments.string("new_text") ?? arguments.string("new_string") else {
            throw AgentToolError.invalidArguments("filePath, oldText, and newText are required")
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
    public let description = "Apply multiple exact text replacements atomically to one workspace file. Every oldText must occur exactly once in the original file."
    public let permission: AgentPermissionCapability = .editWorkspaceFile
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "filePath": .string(description: "Path to edit inside the workspace."),
        "edits": .array(
            items: .closedObject(properties: [
                "oldText": .string(description: "Exact text to replace. Must occur exactly once in the original file."),
                "newText": .string(description: "Replacement text.")
            ], required: ["oldText", "newText"]),
            description: "Ordered list of exact replacements to validate against the original file and then apply atomically."
        )
    ], required: ["filePath", "edits"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawPath = arguments.string("filePath") ?? arguments.string("file_path") ?? arguments.string("path"), let rawEdits = arguments.array("edits") else {
            throw AgentToolError.invalidArguments("filePath and edits are required")
        }
        let edits: [(oldText: String, newText: String)] = try rawEdits.map { value in
            guard let object = value.objectValue,
                  let oldText = object["oldText"]?.stringValue ?? object["old_text"]?.stringValue ?? object["old_string"]?.stringValue,
                  let newText = object["newText"]?.stringValue ?? object["new_text"]?.stringValue ?? object["new_string"]?.stringValue else {
                throw AgentToolError.invalidArguments("Each edit requires oldText and newText")
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

public struct LocalReadManyTool: AgentTool {
    public let name = "ReadMany"
    public let description = "Read multiple text files from the configured local workspace in a single call. Prefer this over separate Read calls when a task needs several files: every file is returned in one turn. Each request supports optional 1-based line offset and limit, and truncated windows return nextOffset so you can continue reading a large file in chunks; a per-file error does not fail the whole batch. Paths must stay inside allowed workspace roots."
    public let permission: AgentPermissionCapability = .readWorkspaceFile
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "requests": .array(
            items: .closedObject(properties: [
                "filePath": .string(description: "Path to a file inside the workspace."),
                "offset": .integer(description: "Optional 1-based line number to start reading from."),
                "limit": .integer(description: "Optional maximum number of lines to return.")
            ], required: ["filePath"]),
            description: "Files to read. Each item is read independently and concurrently."
        )
    ], required: ["requests"])

    private let policy: LocalWorkspacePolicy
    private let perFileByteLimit: Int
    private let batchByteLimit: Int

    public init(policy: LocalWorkspacePolicy) {
        self.policy = policy
        // Bound a single ReadMany result so a large fan-out cannot flood context:
        // cap each file to the shell output budget and the whole batch to 4x it.
        self.perFileByteLimit = policy.maxToolOutputBytes
        self.batchByteLimit = policy.maxToolOutputBytes * 4
    }

    private struct Request: Sendable {
        var index: Int
        var filePath: String
        var offset: Int
        var limit: Int?
    }

    private struct FileOutcome: Sendable {
        var index: Int
        var filePath: String
        var content: String
        var offset: Int
        var limit: Int
        var lineCount: Int
        var truncated: Bool
        var error: String?
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawRequests = arguments.array("requests") else {
            throw AgentToolError.invalidArguments("requests is required")
        }
        guard !rawRequests.isEmpty else {
            throw AgentToolError.invalidArguments("requests must not be empty")
        }
        var parsed: [Request] = []
        for (index, value) in rawRequests.enumerated() {
            guard let object = value.objectValue,
                  let filePath = object["filePath"]?.stringValue ?? object["file_path"]?.stringValue else {
                throw AgentToolError.invalidArguments("Each request requires filePath")
            }
            let offset = max(object["offset"]?.intValue ?? 1, 1)
            let limit = object["limit"]?.intValue.map { max($0, 0) }
            parsed.append(Request(index: index, filePath: filePath, offset: offset, limit: limit))
        }

        let policy = self.policy
        let outcomes = await AgentToolBatchScheduler(maximumConcurrency: 4).run(parsed) { request -> FileOutcome in
            do {
                let path = try policy.resolvePath(request.filePath)
                try policy.validateReadablePath(path)
                try policy.validateReadableSize(path: path)
                let text = try String(contentsOf: path, encoding: .utf8)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let limit = max(request.limit ?? min(lines.count, 2000), 0)
                let start = min(request.offset - 1, lines.count)
                let end = min(start + limit, lines.count)
                let selected = lines[start..<end].enumerated().map { offset, line in
                    "\(start + offset + 1): \(line)"
                }.joined(separator: "\n")
                let truncated = end < lines.count
                return FileOutcome(index: request.index, filePath: path.path, content: selected, offset: request.offset, limit: limit, lineCount: lines.count, truncated: truncated, error: nil)
            } catch {
                return FileOutcome(index: request.index, filePath: request.filePath, content: "", offset: request.offset, limit: request.limit ?? 0, lineCount: 0, truncated: false, error: String(describing: error))
            }
        }

        var remaining = batchByteLimit
        let resultObjects: [[String: Any]] = outcomes.sorted { $0.index < $1.index }.map { outcome in
            var value: [String: Any] = [
                "filePath": outcome.filePath,
                "offset": outcome.offset,
                "limit": outcome.limit,
                "lineCount": outcome.lineCount
            ]
            if let error = outcome.error {
                value["error"] = error
                value["truncated"] = outcome.truncated
                return value
            }
            let (clipped, contentTruncated) = LocalReadManyTool.clip(outcome.content, toBytes: min(perFileByteLimit, remaining))
            remaining = max(0, remaining - clipped.utf8.count)
            value["content"] = clipped
            value["truncated"] = outcome.truncated || contentTruncated
            if outcome.truncated && !contentTruncated {
                value["nextOffset"] = outcome.offset + outcome.limit
            }
            return value
        }
        let json = LocalToolJSON.encode(["results": resultObjects]) ?? "{}"
        let successCount = outcomes.filter { $0.error == nil }.count
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: json,
            contentJSON: json,
            error: successCount == 0 ? "All \(outcomes.count) reads failed" : nil
        )
    }

    static func clip(_ text: String, toBytes limit: Int) -> (String, Bool) {
        let bytes = Array(text.utf8)
        guard bytes.count > max(0, limit) else { return (text, false) }
        let head = String(decoding: bytes.prefix(max(0, limit)), as: UTF8.self)
        return (head + "\n[truncated]", true)
    }
}

public struct LocalApplyPatchTool: AgentTool {
    public let name = "ApplyPatch"
    public let description = "Apply an ordered set of structured file changes inside the workspace. Operations are create, edit, multiedit, or delete. The complete patch is validated against projected file contents before commit; a failed commit is rolled back. Use Shell to inspect files before constructing the patch. Example: {\"operations\":[{\"op\":\"create\",\"filePath\":\"notes/plan.md\",\"content\":\"# Plan\\n\"},{\"op\":\"edit\",\"filePath\":\"notes/plan.md\",\"oldText\":\"# Plan\",\"newText\":\"# Roadmap\"}]}. Use op create with content for new files, op edit with oldText/newText for a unique replacement, op multiedit with an edits array for several replacements in one file, and op delete to remove a file."
    public let permission: AgentPermissionCapability = .editWorkspaceFile
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "operations": .array(
            items: .closedObject(properties: [
                "op": .stringEnumeration(values: ["create", "edit", "multiedit", "delete"], description: "Patch operation."),
                "filePath": .string(description: "Path to write inside the workspace."),
                "content": .string(description: "Full file content for 'create'."),
                "oldText": .string(description: "Exact text to replace for 'edit'. Must occur exactly once in the projected file."),
                "newText": .string(description: "Replacement text for 'edit'."),
                "edits": .array(items: .closedObject(properties: [
                    "oldText": .string(description: "Exact text to replace. Must occur exactly once in the projected file."),
                    "newText": .string(description: "Replacement text.")
                ], required: ["oldText", "newText"]), description: "Ordered replacements for 'multiedit'.")
            ], required: ["op", "filePath"]),
            description: "Ordered patch operations. Applied top to bottom against projected copies, then committed with rollback on failure."
        )
    ], required: ["operations"])

    private let policy: LocalWorkspacePolicy

    public init(policy: LocalWorkspacePolicy) { self.policy = policy }

    /// 在 schema 严格校验之前把模型常见的错误字段写法归一化（真实使用中模型常把
    /// filePath 写成 path、把 create 的整文件内容写成 value、把操作写成 add/replace/remove，
    /// 或漏写 op），让这些意图明确的调用变成合法 operations，避免 ApplyPatch 反复报参数错误。
    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        guard let operations = arguments.array("operations") else { return arguments }
        var values = arguments.values
        values["operations"] = .array(operations.map(Self.normalizeOperation))
        return AgentToolArguments(values: values)
    }

    private static func normalizeOperation(_ value: SendableJSONValue) -> SendableJSONValue {
        guard case .object(var dict) = value else { return value }
        // value -> content：模型常把 create 的整文件内容写成 value。
        if dict["content"] == nil, let content = dict["value"] {
            dict["content"] = content
        }
        dict.removeValue(forKey: "value")
        // 缺 op 时按字段推断，避免 “operations[i].op is required”。
        if dict["op"] == nil {
            if dict["edits"] != nil { dict["op"] = .string("multiedit") }
            else if dict["content"] != nil { dict["op"] = .string("create") }
            else if dict["oldText"] != nil || dict["newText"] != nil { dict["op"] = .string("edit") }
        }
        // op 别名归一化：add/insert/upsert/append -> create；replace/modify/update/change -> edit；remove -> delete。
        if case .string(let op)? = dict["op"], let canonical = Self.canonicalOperationName(op) {
            dict["op"] = .string(canonical)
        }
        // 嵌套 edits 字段别名兜底（schema 别名也会归一化，这里再兜一层）。
        if case .array(let edits)? = dict["edits"] {
            dict["edits"] = .array(edits.map(Self.normalizeEdit))
        }
        return .object(dict)
    }

    private static func normalizeEdit(_ value: SendableJSONValue) -> SendableJSONValue {
        guard case .object(var dict) = value else { return value }
        if dict["oldText"] == nil, let old = dict["old_string"] ?? dict["old_text"] { dict["oldText"] = old }
        if dict["newText"] == nil, let new = dict["new_string"] ?? dict["new_text"] { dict["newText"] = new }
        dict.removeValue(forKey: "old_string")
        dict.removeValue(forKey: "old_text")
        dict.removeValue(forKey: "new_string")
        dict.removeValue(forKey: "new_text")
        return .object(dict)
    }

    private static func canonicalOperationName(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "create", "add", "insert", "upsert", "write", "new": return "create"
        case "edit", "replace", "modify", "update", "change", "patch": return "edit"
        case "multiedit", "multi_edit", "multi-edit": return "multiedit"
        case "delete", "remove": return "delete"
        default: return nil
        }
    }

    private enum Op {
        case create(content: String)
        case edit(oldText: String, newText: String)
        case multiedit(edits: [(oldText: String, newText: String)])
        case delete

        var label: String {
            switch self {
            case .create: return "create"
            case .edit: return "edit"
            case .multiedit: return "multiedit"
            case .delete: return "delete"
            }
        }
    }

    private struct ParsedOperation {
        var index: Int
        var path: URL
        var op: Op
    }

    private enum OriginalFileState {
        case missing
        case contents(Data)
    }

    public func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        // Surface the full batch scope in the single approval prompt so one
        // approval covers every file the batch will create or edit.
        guard let arguments = try? AgentToolArguments(json: call.argumentsJSON),
              let rawOps = arguments.array("operations") else {
            return call.argumentsJSON
        }
        let summary: [[String: Any]] = rawOps.enumerated().compactMap { index, value in
            guard let object = value.objectValue,
                  let op = object["op"]?.stringValue,
                  let path = object["filePath"]?.stringValue ?? object["file_path"]?.stringValue ?? object["path"]?.stringValue else {
                return nil
            }
            return ["index": index, "op": op, "filePath": path]
        }
        return LocalToolJSON.encode(["operations": summary]) ?? call.argumentsJSON
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawOps = arguments.array("operations") else {
            throw AgentToolError.invalidArguments("operations is required")
        }
        guard !rawOps.isEmpty else { throw AgentToolError.invalidArguments("operations must not be empty") }

        var operations: [ParsedOperation] = []
        for (index, value) in rawOps.enumerated() {
            guard let object = value.objectValue,
                  let opName = object["op"]?.stringValue?.lowercased(),
                  let rawPath = object["filePath"]?.stringValue ?? object["file_path"]?.stringValue ?? object["path"]?.stringValue else {
                throw AgentToolError.invalidArguments("Each operation requires op and filePath")
            }
            let path = try policy.resolvePath(rawPath)
            switch opName {
            case "create":
                guard let content = object["content"]?.stringValue else {
                    throw AgentToolError.invalidArguments("operation \(index) (create) requires content")
                }
                operations.append(ParsedOperation(index: index, path: path, op: .create(content: content)))
            case "edit":
                guard let oldText = object["oldText"]?.stringValue ?? object["old_text"]?.stringValue ?? object["old_string"]?.stringValue,
                      let newText = object["newText"]?.stringValue ?? object["new_text"]?.stringValue ?? object["new_string"]?.stringValue else {
                    throw AgentToolError.invalidArguments("operation \(index) (edit) requires oldText and newText")
                }
                operations.append(ParsedOperation(index: index, path: path, op: .edit(oldText: oldText, newText: newText)))
            case "multiedit":
                guard let rawEdits = object["edits"]?.arrayValue else {
                    throw AgentToolError.invalidArguments("operation \(index) (multiedit) requires edits")
                }
                let edits: [(oldText: String, newText: String)] = try rawEdits.map { editValue in
                    guard let editObject = editValue.objectValue,
                          let oldText = editObject["oldText"]?.stringValue ?? editObject["old_text"]?.stringValue ?? editObject["old_string"]?.stringValue,
                          let newText = editObject["newText"]?.stringValue ?? editObject["new_text"]?.stringValue ?? editObject["new_string"]?.stringValue else {
                        throw AgentToolError.invalidArguments("operation \(index) (multiedit) each edit requires oldText and newText")
                    }
                    return (oldText, newText)
                }
                guard !edits.isEmpty else { throw AgentToolError.invalidArguments("operation \(index) (multiedit) edits must not be empty") }
                operations.append(ParsedOperation(index: index, path: path, op: .multiedit(edits: edits)))
            case "delete":
                operations.append(ParsedOperation(index: index, path: path, op: .delete))
            default:
                throw AgentToolError.invalidArguments("operation \(index) has unsupported op '\(opName)'; use create, edit, multiedit, or delete")
            }
        }

        if operations.contains(where: { if case .delete = $0.op { true } else { false } }),
           !context.approvedCapabilities.contains(.deleteWorkspaceFile) {
            let payload = LocalToolJSON.encode(["operations": operations.map {
                ["index": $0.index, "op": $0.op.label, "filePath": $0.path.path]
            }]) ?? "{}"
            let decision = await context.policyEngine.evaluate(
                capability: .deleteWorkspaceFile,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: name,
                payloadJSON: payload
            )
            switch decision.outcome {
            case .approved:
                break
            case .needsApproval:
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: decision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: .deleteWorkspaceFile,
                    toolName: name,
                    payloadJSON: payload
                ))
            case .denied:
                throw AgentToolError.permissionDenied(decision.reason)
            }
        }

        // Phase 1: validate every operation against a projected in-memory copy.
        // Any failure aborts the whole batch before a single byte is written.
        var projected: [String: String] = [:]
        var deletedPaths = Set<String>()
        var seenInBatch = Set<String>()
        var orderedPaths: [String] = []
        for operation in operations {
            let key = operation.path.path
            switch operation.op {
            case .create(let content):
                let alreadyStaged = seenInBatch.contains(key)
                let existsOnDisk = FileManager.default.fileExists(atPath: key)
                try policy.validateWritablePath(operation.path, operation: (existsOnDisk || alreadyStaged) ? .overwriteFile : .createFile)
                projected[key] = content
                deletedPaths.remove(key)
            case .edit(let oldText, let newText):
                try policy.validateWritablePath(operation.path, operation: .editFile)
                let current = try projectedContent(for: operation.path, key: key, projected: projected, deletedPaths: deletedPaths)
                projected[key] = try LocalTextEditor.replacingUnique(original: current, oldText: oldText, newText: newText)
            case .multiedit(let edits):
                try policy.validateWritablePath(operation.path, operation: .editFile)
                let current = try projectedContent(for: operation.path, key: key, projected: projected, deletedPaths: deletedPaths)
                projected[key] = try LocalTextEditor.applyingAtomicEdits(original: current, edits: edits)
            case .delete:
                try policy.validateWritablePath(operation.path, operation: .deleteFile)
                guard projected[key] != nil || FileManager.default.fileExists(atPath: key), !deletedPaths.contains(key) else {
                    throw AgentToolError.invalidArguments("operation \(operation.index) (delete) requires an existing projected file")
                }
                projected.removeValue(forKey: key)
                deletedPaths.insert(key)
            }
            if seenInBatch.insert(key).inserted { orderedPaths.append(key) }
        }
        for key in orderedPaths where !deletedPaths.contains(key) {
            guard let content = projected[key] else {
                throw AgentToolError.invalidArguments("No projected content for \(key)")
            }
            try policy.validateWritableSize(path: URL(fileURLWithPath: key), content: content)
        }

        var originals: [String: OriginalFileState] = [:]
        for key in orderedPaths {
            originals[key] = FileManager.default.fileExists(atPath: key)
                ? .contents(try Data(contentsOf: URL(fileURLWithPath: key)))
                : .missing
        }
        var committed: [String] = []
        do {
            for key in orderedPaths {
                let url = URL(fileURLWithPath: key)
                if deletedPaths.contains(key) {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try (projected[key] ?? "").write(to: url, atomically: true, encoding: .utf8)
                }
                committed.append(key)
            }
        } catch {
            var rollbackErrors: [String] = []
            for key in committed.reversed() {
                let url = URL(fileURLWithPath: key)
                do {
                    switch originals[key] {
                    case .contents(let data):
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: url, options: .atomic)
                    case .missing:
                        if FileManager.default.fileExists(atPath: key) { try FileManager.default.removeItem(at: url) }
                    case nil:
                        break
                    }
                } catch {
                    rollbackErrors.append("\(key): \(error)")
                }
            }
            if !rollbackErrors.isEmpty {
                throw AgentToolError.invalidArguments("Patch commit failed and rollback was incomplete: \(rollbackErrors.joined(separator: "; "))")
            }
            throw error
        }

        let operationsReport: [[String: Any]] = operations.map { operation in
            ["index": operation.index, "filePath": operation.path.path, "op": operation.op.label]
        }
        let json = LocalToolJSON.encode([
            "filesChanged": orderedPaths.count,
            "operations": operationsReport,
            "success": true
        ]) ?? "{}"
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Applied \(operations.count) operations across \(orderedPaths.count) files.",
            contentJSON: json
        )
    }

    private func projectedContent(for path: URL, key: String, projected: [String: String], deletedPaths: Set<String>) throws -> String {
        guard !deletedPaths.contains(key) else {
            throw AgentToolError.invalidArguments("Cannot edit a file after deleting it without creating it again: \(key)")
        }
        if let staged = projected[key] { return staged }
        try policy.validateReadablePath(path)
        return try String(contentsOf: path, encoding: .utf8)
    }
}

private extension SendableJSONValue {
    var arrayValue: [SendableJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }
}

enum LocalTextEditor {
    static func replacingUnique(original: String, oldText: String, newText: String) throws -> String {
        guard !oldText.isEmpty else { throw AgentToolError.invalidArguments("oldText must not be empty") }
        let ranges = ranges(of: oldText, in: original)
        guard ranges.count == 1 else {
            throw AgentToolError.invalidArguments("oldText must occur exactly once; found \(ranges.count)")
        }
        return original.replacingCharacters(in: ranges[0], with: newText)
    }

    static func applyingAtomicEdits(original: String, edits: [(oldText: String, newText: String)]) throws -> String {
        for edit in edits {
            let ranges = ranges(of: edit.oldText, in: original)
            guard ranges.count == 1 else {
                throw AgentToolError.invalidArguments("oldText must occur exactly once; found \(ranges.count): \(edit.oldText)")
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
        let captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-shell-capture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }

        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
              FileManager.default.createFile(atPath: stderrURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()

        let timeoutState = LocalShellTimeoutState()
        let timeoutTimer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.connor.local-shell-timeout.(UUID().uuidString)")
        )
        timeoutTimer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timeoutTimer.setEventHandler {
            timeoutState.terminateIfRunning(process)
        }
        timeoutTimer.resume()
        defer {
            timeoutTimer.setEventHandler {}
            timeoutTimer.cancel()
        }

        while process.isRunning {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if timeoutState.didTimeout {
            process.waitUntilExit()
            throw LocalWorkspacePolicyError.commandTimedOut(command)
        }
        try stdoutHandle.close()
        try stderrHandle.close()
        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)
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
        let headCount = max(maxBytes / 2, 0)
        let tailCount = max(maxBytes - headCount, 0)
        let head = String(decoding: bytes.prefix(headCount), as: UTF8.self)
        let tail = String(decoding: bytes.suffix(tailCount), as: UTF8.self)
        return (head + "\n[truncated to \(maxBytes) bytes; middle omitted]\n" + tail, true)
    }
}

private final class LocalShellTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeout: Bool {
        lock.withLock { timedOut }
    }

    func terminateIfRunning(_ process: Process) {
        lock.withLock {
            guard process.isRunning else { return }
            timedOut = true
            process.terminate()
        }
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
