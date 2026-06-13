import Foundation

public enum LocalWorkspacePolicyError: Error, Sendable, Equatable, CustomStringConvertible {
    case pathEscapesAllowedRoots(String)
    case protectedPath(String)
    case missingParentDirectory(String)
    case notDirectory(String)
    case invalidPath(String)
    case fileTooLarge(path: String, bytes: Int, limit: Int)
    case writeTooLarge(path: String, bytes: Int, limit: Int)
    case commandDenied(String)
    case commandTimedOut(String)

    public var description: String {
        switch self {
        case .pathEscapesAllowedRoots(let path): return "Path escapes allowed workspace roots: \(path)"
        case .protectedPath(let path): return "Path is protected by local workspace policy: \(path)"
        case .missingParentDirectory(let path): return "Parent directory does not exist: \(path)"
        case .notDirectory(let path): return "Expected directory: \(path)"
        case .invalidPath(let path): return "Invalid path: \(path)"
        case .fileTooLarge(let path, let bytes, let limit): return "File too large to read: \(path) (\(bytes) bytes > \(limit) bytes)"
        case .writeTooLarge(let path, let bytes, let limit): return "Content too large to write: \(path) (\(bytes) bytes > \(limit) bytes)"
        case .commandDenied(let reason): return "Command denied: \(reason)"
        case .commandTimedOut(let command): return "Command timed out: \(command)"
        }
    }
}

public enum FileMutationOperation: String, Sendable, Equatable {
    case createFile
    case overwriteFile
    case editFile
    case deleteFile
}

public enum ShellCommandRisk: String, Sendable, Equatable, Codable {
    case readOnly
    case workspaceWrite
    case network
    case destructive
    case unknown
}

public struct ShellCommandClassification: Sendable, Equatable, Codable {
    public var risk: ShellCommandRisk
    public var reason: String

    public init(risk: ShellCommandRisk, reason: String) {
        self.risk = risk
        self.reason = reason
    }
}

public struct LocalWorkspacePolicy: Sendable, Equatable {
    public var workingDirectory: URL
    public var additionalAllowedDirectories: [URL]
    public var maxReadBytes: Int
    public var maxWriteBytes: Int
    public var maxSearchResults: Int
    public var maxToolOutputBytes: Int

    private var allowedRoots: [URL] {
        ([workingDirectory] + additionalAllowedDirectories).map { Self.canonicalDirectoryURL($0) }
    }

    public init(
        workingDirectory: URL,
        additionalAllowedDirectories: [URL] = [],
        maxReadBytes: Int = 1_048_576,
        maxWriteBytes: Int = 1_048_576,
        maxSearchResults: Int = 100,
        maxToolOutputBytes: Int = 32_768
    ) {
        self.workingDirectory = Self.canonicalDirectoryURL(workingDirectory)
        self.additionalAllowedDirectories = additionalAllowedDirectories.map { Self.canonicalDirectoryURL($0) }
        self.maxReadBytes = maxReadBytes
        self.maxWriteBytes = maxWriteBytes
        self.maxSearchResults = maxSearchResults
        self.maxToolOutputBytes = maxToolOutputBytes
    }

    public static func `default`(workingDirectory: URL) -> LocalWorkspacePolicy {
        LocalWorkspacePolicy(workingDirectory: workingDirectory)
    }

    public func resolvePath(_ rawPath: String, base: URL? = nil) throws -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalWorkspacePolicyError.invalidPath(rawPath) }

        let candidate: URL
        if trimmed.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let suffix = String(trimmed.dropFirst())
            candidate = URL(fileURLWithPath: home + suffix)
        } else if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            candidate = (base ?? workingDirectory).appendingPathComponent(trimmed)
        }

        let canonical = canonicalURLForExistingPathOrParent(candidate)
        guard isInsideAllowedRoots(canonical) else {
            throw LocalWorkspacePolicyError.pathEscapesAllowedRoots(canonical.path)
        }
        return canonical
    }

    public func validateReadablePath(_ url: URL) throws {
        let canonical = canonicalURLForExistingPathOrParent(url)
        guard isInsideAllowedRoots(canonical) else {
            throw LocalWorkspacePolicyError.pathEscapesAllowedRoots(canonical.path)
        }
        try rejectProtectedPath(canonical, operation: nil)
    }

    public func validateSearchScope(_ url: URL) throws {
        let canonical = canonicalURLForExistingPathOrParent(url)
        guard isInsideAllowedRoots(canonical) else {
            throw LocalWorkspacePolicyError.pathEscapesAllowedRoots(canonical.path)
        }
        try rejectProtectedPath(canonical, operation: nil)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw LocalWorkspacePolicyError.notDirectory(canonical.path)
        }
    }

    public func validateWritablePath(_ url: URL, operation: FileMutationOperation) throws {
        let canonical = canonicalURLForExistingPathOrParent(url)
        guard isInsideAllowedRoots(canonical) else {
            throw LocalWorkspacePolicyError.pathEscapesAllowedRoots(canonical.path)
        }
        try rejectProtectedPath(canonical, operation: operation)
        let parent = canonical.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LocalWorkspacePolicyError.notDirectory(parent.path) }
        } else {
            let existingAncestor = nearestExistingAncestor(parent)
            var ancestorIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: existingAncestor.path, isDirectory: &ancestorIsDirectory), ancestorIsDirectory.boolValue else {
                throw LocalWorkspacePolicyError.missingParentDirectory(parent.path)
            }
            guard isInsideAllowedRoots(existingAncestor) else {
                throw LocalWorkspacePolicyError.pathEscapesAllowedRoots(parent.path)
            }
            try rejectProtectedPath(parent, operation: operation)
        }
    }

    public func validateReadableSize(path: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let size = attributes[.size] as? Int ?? 0
        if size > maxReadBytes {
            throw LocalWorkspacePolicyError.fileTooLarge(path: path.path, bytes: size, limit: maxReadBytes)
        }
    }

    public func validateWritableSize(path: URL, content: String) throws {
        let bytes = content.data(using: .utf8)?.count ?? content.utf8.count
        if bytes > maxWriteBytes {
            throw LocalWorkspacePolicyError.writeTooLarge(path: path.path, bytes: bytes, limit: maxWriteBytes)
        }
    }

    public func classifyCommand(_ command: String) -> ShellCommandClassification {
        LocalShellCommandPolicy.classify(command)
    }

    private func isInsideAllowedRoots(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return allowedRoots.contains { root in
            let rootPath = normalizedPath(root)
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private func rejectProtectedPath(_ url: URL, operation: FileMutationOperation?) throws {
        let path = normalizedPath(url)
        let components = url.pathComponents
        let basename = url.lastPathComponent

        if components.contains(".git") {
            if operation != nil || components.contains("objects") || components.contains("index") {
                throw LocalWorkspacePolicyError.protectedPath(path)
            }
        }
        if basename == ".env" || basename.hasPrefix(".env.") {
            if operation != nil { throw LocalWorkspacePolicyError.protectedPath(path) }
        }
        let protectedHomeFragments = ["/.ssh/", "/.gnupg/", "/.aws/"]
        if protectedHomeFragments.contains(where: { path.contains($0) }) {
            throw LocalWorkspacePolicyError.protectedPath(path)
        }
    }

    private func nearestExistingAncestor(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.path) {
                return current.resolvingSymlinksInPath().standardizedFileURL
            }
            current.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }

    private func canonicalURLForExistingPathOrParent(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().standardizedFileURL
        }
        let parent = standardized.deletingLastPathComponent()
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        return resolvedParent.appendingPathComponent(standardized.lastPathComponent).standardizedFileURL
    }

    private static func canonicalDirectoryURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

public enum LocalShellCommandPolicy {
    public static func classify(_ command: String) -> ShellCommandClassification {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ShellCommandClassification(risk: .unknown, reason: "empty command")
        }
        let lower = trimmed.lowercased()
        let destructivePatterns = ["rm -rf /", "sudo ", " chown ", "chmod -r", "diskutil", "mkfs", ":(){", "killall "]
        if destructivePatterns.contains(where: { lower.contains($0) }) {
            return ShellCommandClassification(risk: .destructive, reason: "matches destructive shell pattern")
        }
        let networkPrefixes = ["curl ", "wget ", "git fetch", "git pull", "git push", "npm install", "npm update", "swift package resolve"]
        if networkPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return ShellCommandClassification(risk: .network, reason: "network or dependency command")
        }
        let writePrefixes = ["mkdir ", "touch ", "cp ", "mv ", "rm ", "sed -i", "python ", "python3 ", "node ", "npm run"]
        if writePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return ShellCommandClassification(risk: .workspaceWrite, reason: "may mutate workspace")
        }
        let readOnlyPrefixes = ["pwd", "ls", "cat ", "sed -n", "grep ", "rg ", "find ", "git status", "git diff", "swift test", "swift build", "xcodebuild test"]
        if readOnlyPrefixes.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0) }) {
            return ShellCommandClassification(risk: .readOnly, reason: "recognized read-only or verification command")
        }
        return ShellCommandClassification(risk: .unknown, reason: "command is not in local policy allowlist")
    }
}
