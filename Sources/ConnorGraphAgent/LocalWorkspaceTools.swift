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
