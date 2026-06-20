import Foundation

public enum AppProjectWorkingDirectorySource: String, Codable, Sendable, Equatable {
    case session
    case runtimeSettings
    case processCurrentDirectory
}

public struct ResolvedProjectWorkingDirectory: Sendable, Equatable {
    public var url: URL
    public var source: AppProjectWorkingDirectorySource

    public init(url: URL, source: AppProjectWorkingDirectorySource) {
        self.url = AppProjectWorkingDirectoryResolver.canonicalDirectoryURL(url)
        self.source = source
    }

    public var path: String { url.path }
}

public struct ResolvedProjectWorkspaceRoot: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var url: URL
    public var role: String
    public var isPrimary: Bool
    public var source: AppProjectWorkingDirectorySource

    public init(
        id: String,
        displayName: String,
        url: URL,
        role: String,
        isPrimary: Bool,
        source: AppProjectWorkingDirectorySource
    ) {
        self.id = id
        self.displayName = displayName
        self.url = AppProjectWorkingDirectoryResolver.canonicalDirectoryURL(url)
        self.role = role
        self.isPrimary = isPrimary
        self.source = source
    }
}

public struct ResolvedProjectWorkspace: Sendable, Equatable {
    public var primary: ResolvedProjectWorkingDirectory
    public var roots: [ResolvedProjectWorkspaceRoot]

    public init(primary: ResolvedProjectWorkingDirectory, roots: [ResolvedProjectWorkspaceRoot]) {
        self.primary = primary
        self.roots = roots
    }

    public var additionalAllowedDirectories: [URL] {
        roots
            .filter { AppProjectWorkingDirectoryResolver.normalizedPath($0.url) != AppProjectWorkingDirectoryResolver.normalizedPath(primary.url) }
            .map(\.url)
    }
}

public enum AppProjectWorkingDirectoryResolver {
    public static func resolve(
        sessionWorkingDirectoryPath: String? = nil,
        runtimeSettings: AgentRuntimeSettings,
        llmSettings: AppLLMSettings,
        processCurrentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> ResolvedProjectWorkingDirectory {
        resolveWorkspace(
            sessionWorkingDirectoryPath: sessionWorkingDirectoryPath,
            runtimeSettings: runtimeSettings,
            llmSettings: llmSettings,
            processCurrentDirectoryPath: processCurrentDirectoryPath
        ).primary
    }

    public static func resolveWorkspace(
        sessionWorkingDirectoryPath: String? = nil,
        sessionWorkspaceRoots: [AppSessionWorkspaceRootReference] = [],
        runtimeSettings: AgentRuntimeSettings,
        llmSettings: AppLLMSettings,
        processCurrentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> ResolvedProjectWorkspace {
        let sessionRoots = resolvedSessionRoots(sessionWorkspaceRoots)
        if let sessionPrimary = sessionRoots.first(where: \.isPrimary) ?? sessionRoots.first {
            return ResolvedProjectWorkspace(
                primary: ResolvedProjectWorkingDirectory(url: sessionPrimary.url, source: .session),
                roots: normalizePrimary(in: sessionRoots, primaryID: sessionPrimary.id)
            )
        }

        if let url = directoryURL(from: sessionWorkingDirectoryPath) {
            let root = ResolvedProjectWorkspaceRoot(
                id: "session-primary",
                displayName: url.lastPathComponent,
                url: url,
                role: "project",
                isPrimary: true,
                source: .session
            )
            return ResolvedProjectWorkspace(primary: ResolvedProjectWorkingDirectory(url: url, source: .session), roots: [root])
        }

        let runtimeRoots = resolvedRuntimeRoots(runtimeSettings.workspace.effectiveRoots())
        if let runtimePrimary = runtimeRoots.first(where: \.isPrimary) ?? runtimeRoots.first {
            return ResolvedProjectWorkspace(
                primary: ResolvedProjectWorkingDirectory(url: runtimePrimary.url, source: .runtimeSettings),
                roots: normalizePrimary(in: runtimeRoots, primaryID: runtimePrimary.id)
            )
        }

        let processURL = URL(fileURLWithPath: processCurrentDirectoryPath, isDirectory: true)
        let root = ResolvedProjectWorkspaceRoot(
            id: "process-current-directory",
            displayName: processURL.lastPathComponent,
            url: processURL,
            role: "process",
            isPrimary: true,
            source: .processCurrentDirectory
        )
        return ResolvedProjectWorkspace(primary: ResolvedProjectWorkingDirectory(url: processURL, source: .processCurrentDirectory), roots: [root])
    }

    public static func additionalAllowedDirectories(from runtimeSettings: AgentRuntimeSettings) -> [URL] {
        let roots = resolvedRuntimeRoots(runtimeSettings.workspace.effectiveRoots())
        if !roots.isEmpty {
            let primary = roots.first(where: \.isPrimary) ?? roots.first
            return roots
                .filter { normalizedPath($0.url) != normalizedPath(primary?.url ?? $0.url) }
                .map(\.url)
        }
        return runtimeSettings.workspace.additionalAllowedDirectoryPaths.compactMap { directoryURL(from: $0) }
    }

    fileprivate static func canonicalDirectoryURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = canonicalDirectoryURL(url).path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    fileprivate static func normalizedPath(_ url: URL) -> String {
        normalizedDirectoryPath(url)
    }

    private static func resolvedRuntimeRoots(_ roots: [AgentRuntimeWorkspaceRoot]) -> [ResolvedProjectWorkspaceRoot] {
        roots.compactMap { root in
            guard let url = directoryURL(from: root.path) else { return nil }
            return ResolvedProjectWorkspaceRoot(
                id: root.id,
                displayName: root.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.lastPathComponent : root.displayName,
                url: url,
                role: root.role,
                isPrimary: root.isPrimary,
                source: .runtimeSettings
            )
        }
    }

    private static func resolvedSessionRoots(_ roots: [AppSessionWorkspaceRootReference]) -> [ResolvedProjectWorkspaceRoot] {
        roots.compactMap { root in
            guard let url = directoryURL(from: root.path) else { return nil }
            return ResolvedProjectWorkspaceRoot(
                id: root.id,
                displayName: root.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.lastPathComponent : root.displayName,
                url: url,
                role: root.role,
                isPrimary: root.isPrimary,
                source: .session
            )
        }
    }

    private static func normalizePrimary(in roots: [ResolvedProjectWorkspaceRoot], primaryID: String) -> [ResolvedProjectWorkspaceRoot] {
        roots.map { root in
            var normalized = root
            normalized.isPrimary = root.id == primaryID
            return normalized
        }
    }

    private static func directoryURL(from rawPath: String?) -> URL? {
        guard let rawPath else { return nil }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return URL(fileURLWithPath: home + String(path.dropFirst()), isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
