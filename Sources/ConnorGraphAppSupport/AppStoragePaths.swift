import Foundation
import ConnorGraphCore

public struct AppStoragePaths: Sendable, Equatable {
    public var applicationSupportDirectory: URL
    public var configDirectory: URL
    public var sessionsDirectory: URL
    public var sourcesDirectory: URL
    public var skillsDirectory: URL
    public var tasksDirectory: URL
    public var automationsDirectory: URL
    public var labelsDirectory: URL
    public var statusesDirectory: URL
    public var artifactsDirectory: URL
    public var graphDirectory: URL
    public var graphIndexesDirectory: URL
    public var graphExportsDirectory: URL
    public var graphSnapshotsDirectory: URL
    public var logsDirectory: URL
    public var auditLogsDirectory: URL
    public var runtimeLogsDirectory: URL
    public var sidecarsDirectory: URL
    public var browserDirectory: URL
    public var searchDirectory: URL
    public var databaseURL: URL
    public var memoryOSDatabaseURL: URL

    public init(
        applicationSupportDirectory: URL,
        configDirectory: URL? = nil,
        sessionsDirectory: URL? = nil,
        sourcesDirectory: URL? = nil,
        skillsDirectory: URL? = nil,
        tasksDirectory: URL? = nil,
        automationsDirectory: URL? = nil,
        labelsDirectory: URL? = nil,
        statusesDirectory: URL? = nil,
        artifactsDirectory: URL? = nil,
        graphDirectory: URL? = nil,
        graphIndexesDirectory: URL? = nil,
        graphExportsDirectory: URL? = nil,
        graphSnapshotsDirectory: URL? = nil,
        logsDirectory: URL? = nil,
        auditLogsDirectory: URL? = nil,
        runtimeLogsDirectory: URL? = nil,
        sidecarsDirectory: URL? = nil,
        browserDirectory: URL? = nil,
        searchDirectory: URL? = nil,
        databaseURL: URL? = nil,
        memoryOSDatabaseURL: URL? = nil
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        let resolvedConfigDirectory = configDirectory ?? applicationSupportDirectory.appendingPathComponent("config", isDirectory: true)
        let resolvedSessionsDirectory = sessionsDirectory ?? applicationSupportDirectory.appendingPathComponent("sessions", isDirectory: true)
        let resolvedSourcesDirectory = sourcesDirectory ?? applicationSupportDirectory.appendingPathComponent("sources", isDirectory: true)
        let resolvedSkillsDirectory = skillsDirectory ?? applicationSupportDirectory.appendingPathComponent("skills", isDirectory: true)
        let resolvedGraphDirectory = graphDirectory ?? applicationSupportDirectory.appendingPathComponent("graph", isDirectory: true)
        let resolvedLogsDirectory = logsDirectory ?? applicationSupportDirectory.appendingPathComponent("logs", isDirectory: true)

        self.configDirectory = resolvedConfigDirectory
        self.sessionsDirectory = resolvedSessionsDirectory
        self.sourcesDirectory = resolvedSourcesDirectory
        self.skillsDirectory = resolvedSkillsDirectory
        self.tasksDirectory = tasksDirectory ?? applicationSupportDirectory.appendingPathComponent("tasks", isDirectory: true)
        self.automationsDirectory = automationsDirectory ?? applicationSupportDirectory.appendingPathComponent("automations", isDirectory: true)
        self.labelsDirectory = labelsDirectory ?? applicationSupportDirectory.appendingPathComponent("labels", isDirectory: true)
        self.statusesDirectory = statusesDirectory ?? applicationSupportDirectory.appendingPathComponent("statuses", isDirectory: true)
        self.artifactsDirectory = artifactsDirectory ?? applicationSupportDirectory.appendingPathComponent("artifacts", isDirectory: true)
        self.graphDirectory = resolvedGraphDirectory
        self.graphIndexesDirectory = graphIndexesDirectory ?? resolvedGraphDirectory.appendingPathComponent("indexes", isDirectory: true)
        self.graphExportsDirectory = graphExportsDirectory ?? resolvedGraphDirectory.appendingPathComponent("exports", isDirectory: true)
        self.graphSnapshotsDirectory = graphSnapshotsDirectory ?? resolvedGraphDirectory.appendingPathComponent("snapshots", isDirectory: true)
        self.logsDirectory = resolvedLogsDirectory
        self.auditLogsDirectory = auditLogsDirectory ?? resolvedLogsDirectory.appendingPathComponent("audit", isDirectory: true)
        self.runtimeLogsDirectory = runtimeLogsDirectory ?? resolvedLogsDirectory.appendingPathComponent("runtime", isDirectory: true)
        self.sidecarsDirectory = sidecarsDirectory ?? applicationSupportDirectory.appendingPathComponent("sidecars", isDirectory: true)
        self.browserDirectory = browserDirectory ?? applicationSupportDirectory.appendingPathComponent("browser", isDirectory: true)
        self.searchDirectory = searchDirectory ?? applicationSupportDirectory.appendingPathComponent("search", isDirectory: true)
        self.databaseURL = databaseURL ?? resolvedGraphDirectory.appendingPathComponent("connor.sqlite")
        self.memoryOSDatabaseURL = memoryOSDatabaseURL ?? resolvedGraphDirectory.appendingPathComponent("memory-os.sqlite")
    }

    public static func live(fileManager: FileManager = .default) throws -> AppStoragePaths {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return resolving(applicationSupportBaseDirectory: base)
    }

    public static func resolving(applicationSupportBaseDirectory: URL) -> AppStoragePaths {
        let directory = applicationSupportBaseDirectory.appendingPathComponent("Connor", isDirectory: true)
        return AppStoragePaths(applicationSupportDirectory: directory)
    }

    public var requiredDirectories: [URL] {
        [
            applicationSupportDirectory,
            configDirectory,
            sessionsDirectory,
            sourcesDirectory,
            skillsDirectory,
            tasksDirectory,
            automationsDirectory,
            labelsDirectory,
            statusesDirectory,
            artifactsDirectory,
            graphDirectory,
            graphIndexesDirectory,
            graphExportsDirectory,
            graphSnapshotsDirectory,
            logsDirectory,
            auditLogsDirectory,
            runtimeLogsDirectory,
            sidecarsDirectory,
            browserDirectory,
            searchDirectory
        ]
    }

    public var browserHistoryURL: URL {
        browserDirectory.appendingPathComponent("history.jsonl")
    }

    public var browserBookmarksURL: URL {
        browserDirectory.appendingPathComponent("bookmarks.jsonl")
    }

    public var nativeSourceSearchDatabaseURL: URL {
        searchDirectory.appendingPathComponent("native-source-search.sqlite")
    }

    public var sessionSearchDatabaseURL: URL {
        searchDirectory.appendingPathComponent("session-search.sqlite")
    }

    public var globalSearchHistoryURL: URL {
        searchDirectory.appendingPathComponent("global-search-history.json")
    }

    public func sessionArtifactDirectories(sessionID: String) -> AgentSessionArtifactDirectories {
        AgentSessionArtifactDirectories(root: sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true))
    }

    public func ensureSessionArtifactDirectories(sessionID: String, fileManager: FileManager = .default) throws -> AgentSessionArtifactDirectories {
        let directories = sessionArtifactDirectories(sessionID: sessionID)
        for directory in directories.all {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directories
    }

    public func ensureDirectoryHierarchy(fileManager: FileManager = .default) throws {
        for directory in requiredDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
