import Foundation

public enum WorkspaceFileNodeKind: String, Sendable, Equatable, Codable {
    case directory
    case package
    case file
    case symbolicLink
}

public struct WorkspaceFileNode: Identifiable, Sendable, Equatable {
    public var id: String
    public var rootID: String
    public var name: String
    public var relativePath: String
    public var url: URL
    public var kind: WorkspaceFileNodeKind
    public var isHidden: Bool
    public var byteCount: Int64?
    public var modificationDate: Date?

    public init(
        id: String,
        rootID: String,
        name: String,
        relativePath: String,
        url: URL,
        kind: WorkspaceFileNodeKind,
        isHidden: Bool,
        byteCount: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.rootID = rootID
        self.name = name
        self.relativePath = relativePath
        self.url = url
        self.kind = kind
        self.isHidden = isHidden
        self.byteCount = byteCount
        self.modificationDate = modificationDate
    }

    public var isExpandable: Bool { kind == .directory }
}

public enum WorkspaceDirectoryLoaderError: Error, Sendable, Equatable, LocalizedError {
    case directoryOutsideRoot(String)
    case notDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .directoryOutsideRoot(let path):
            return "目录不在当前工作区范围内：\(path)"
        case .notDirectory(let path):
            return "无法读取目录：\(path)"
        }
    }
}

public actor WorkspaceDirectoryLoader {
    private struct CacheKey: Hashable {
        var rootID: String
        var directoryPath: String
    }

    private let fileManager: FileManager
    private var cachedChildren: [CacheKey: [WorkspaceFileNode]] = [:]

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func children(
        rootID: String,
        rootURL: URL,
        directoryURL: URL,
        forceRefresh: Bool = false
    ) throws -> [WorkspaceFileNode] {
        let normalizedRoot = Self.normalizedFileURL(rootURL)
        let normalizedDirectory = Self.normalizedFileURL(directoryURL)
        guard Self.contains(normalizedDirectory, in: normalizedRoot) else {
            throw WorkspaceDirectoryLoaderError.directoryOutsideRoot(directoryURL.path)
        }

        let key = CacheKey(rootID: rootID, directoryPath: normalizedDirectory.path)
        if !forceRefresh, let cached = cachedChildren[key] { return cached }

        let values = try normalizedDirectory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw WorkspaceDirectoryLoaderError.notDirectory(directoryURL.path)
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        let entries = try fileManager.contentsOfDirectory(
            at: normalizedDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )
        let nodes = try entries.map { entry in
            let values = try entry.resourceValues(forKeys: resourceKeys)
            let relativePath = Self.relativePath(of: entry, root: normalizedRoot)
            let kind: WorkspaceFileNodeKind
            if values.isSymbolicLink == true {
                kind = .symbolicLink
            } else if values.isPackage == true {
                kind = .package
            } else if values.isDirectory == true {
                kind = .directory
            } else {
                kind = .file
            }
            return WorkspaceFileNode(
                id: "\(rootID):\(relativePath)",
                rootID: rootID,
                name: entry.lastPathComponent,
                relativePath: relativePath,
                url: entry,
                kind: kind,
                isHidden: values.isHidden == true || entry.lastPathComponent.hasPrefix("."),
                byteCount: values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate
            )
        }.sorted(by: Self.sortNodes)

        cachedChildren[key] = nodes
        return nodes
    }

    public func invalidate(rootID: String) {
        cachedChildren = cachedChildren.filter { $0.key.rootID != rootID }
    }

    public func invalidateAll() {
        cachedChildren.removeAll(keepingCapacity: true)
    }

    private static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.path == "/" ? "/" : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.path == "/" ? "/" : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(url.path.dropFirst(rootPath.count))
    }

    private static func sortNodes(_ lhs: WorkspaceFileNode, _ rhs: WorkspaceFileNode) -> Bool {
        let lhsRank = sortRank(lhs.kind)
        let rhsRank = sortRank(rhs.kind)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func sortRank(_ kind: WorkspaceFileNodeKind) -> Int {
        switch kind {
        case .directory: 0
        case .package: 1
        case .file: 2
        case .symbolicLink: 3
        }
    }
}
