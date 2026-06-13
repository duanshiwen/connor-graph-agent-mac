import Foundation

public enum AppProjectWorkingDirectorySource: String, Codable, Sendable, Equatable {
    case session
    case runtimeSettings
    case legacySidecarSettings
    case processCurrentDirectory
}

public struct ResolvedProjectWorkingDirectory: Sendable, Equatable {
    public var url: URL
    public var source: AppProjectWorkingDirectorySource

    public init(url: URL, source: AppProjectWorkingDirectorySource) {
        self.url = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        self.source = source
    }

    public var path: String { url.path }
}

public enum AppProjectWorkingDirectoryResolver {
    public static func resolve(
        sessionWorkingDirectoryPath: String? = nil,
        runtimeSettings: AgentRuntimeSettings,
        llmSettings: AppLLMSettings,
        processCurrentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> ResolvedProjectWorkingDirectory {
        if let url = directoryURL(from: sessionWorkingDirectoryPath) {
            return ResolvedProjectWorkingDirectory(url: url, source: .session)
        }
        if let url = directoryURL(from: runtimeSettings.workspace.defaultWorkingDirectoryPath) {
            return ResolvedProjectWorkingDirectory(url: url, source: .runtimeSettings)
        }
        if let url = directoryURL(from: llmSettings.sidecarWorkingDirectoryPath) {
            return ResolvedProjectWorkingDirectory(url: url, source: .legacySidecarSettings)
        }
        return ResolvedProjectWorkingDirectory(
            url: URL(fileURLWithPath: processCurrentDirectoryPath, isDirectory: true),
            source: .processCurrentDirectory
        )
    }

    public static func additionalAllowedDirectories(from runtimeSettings: AgentRuntimeSettings) -> [URL] {
        runtimeSettings.workspace.additionalAllowedDirectoryPaths.compactMap { directoryURL(from: $0) }
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
