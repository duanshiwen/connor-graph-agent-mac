import Foundation

public struct AppStoragePaths: Sendable, Equatable {
    public var applicationSupportDirectory: URL
    public var configDirectory: URL
    public var sessionsDirectory: URL
    public var sourcesDirectory: URL
    public var skillsDirectory: URL
    public var graphDirectory: URL
    public var graphIndexesDirectory: URL
    public var graphExportsDirectory: URL
    public var graphSnapshotsDirectory: URL
    public var logsDirectory: URL
    public var auditLogsDirectory: URL
    public var runtimeLogsDirectory: URL
    public var sidecarsDirectory: URL
    public var databaseURL: URL

    public init(
        applicationSupportDirectory: URL,
        configDirectory: URL? = nil,
        sessionsDirectory: URL? = nil,
        sourcesDirectory: URL? = nil,
        skillsDirectory: URL? = nil,
        graphDirectory: URL? = nil,
        graphIndexesDirectory: URL? = nil,
        graphExportsDirectory: URL? = nil,
        graphSnapshotsDirectory: URL? = nil,
        logsDirectory: URL? = nil,
        auditLogsDirectory: URL? = nil,
        runtimeLogsDirectory: URL? = nil,
        sidecarsDirectory: URL? = nil,
        databaseURL: URL? = nil
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
        self.graphDirectory = resolvedGraphDirectory
        self.graphIndexesDirectory = graphIndexesDirectory ?? resolvedGraphDirectory.appendingPathComponent("indexes", isDirectory: true)
        self.graphExportsDirectory = graphExportsDirectory ?? resolvedGraphDirectory.appendingPathComponent("exports", isDirectory: true)
        self.graphSnapshotsDirectory = graphSnapshotsDirectory ?? resolvedGraphDirectory.appendingPathComponent("snapshots", isDirectory: true)
        self.logsDirectory = resolvedLogsDirectory
        self.auditLogsDirectory = auditLogsDirectory ?? resolvedLogsDirectory.appendingPathComponent("audit", isDirectory: true)
        self.runtimeLogsDirectory = runtimeLogsDirectory ?? resolvedLogsDirectory.appendingPathComponent("runtime", isDirectory: true)
        self.sidecarsDirectory = sidecarsDirectory ?? applicationSupportDirectory.appendingPathComponent("sidecars", isDirectory: true)
        self.databaseURL = databaseURL ?? resolvedGraphDirectory.appendingPathComponent("connor.sqlite")
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
            graphDirectory,
            graphIndexesDirectory,
            graphExportsDirectory,
            graphSnapshotsDirectory,
            logsDirectory,
            auditLogsDirectory,
            runtimeLogsDirectory,
            sidecarsDirectory
        ]
    }

    public func ensureDirectoryHierarchy(fileManager: FileManager = .default) throws {
        for directory in requiredDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
