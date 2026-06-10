import Foundation
import Testing
import ConnorGraphAppSupport

@Test func appStoragePathsResolveSingleNativeConnorRootWithoutWorkspaceSegments() {
    let base = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)

    #expect(paths.applicationSupportDirectory.path == "/tmp/Application Support/Connor")
    #expect(paths.configDirectory.path == "/tmp/Application Support/Connor/config")
    #expect(paths.sessionsDirectory.path == "/tmp/Application Support/Connor/sessions")
    #expect(paths.sourcesDirectory.path == "/tmp/Application Support/Connor/sources")
    #expect(paths.skillsDirectory.path == "/tmp/Application Support/Connor/skills")
    #expect(paths.graphDirectory.path == "/tmp/Application Support/Connor/graph")
    #expect(paths.logsDirectory.path == "/tmp/Application Support/Connor/logs")
    #expect(paths.sidecarsDirectory.path == "/tmp/Application Support/Connor/sidecars")
    #expect(paths.databaseURL.path == "/tmp/Application Support/Connor/graph/connor.sqlite")

    #expect(!paths.applicationSupportDirectory.path.contains("workspaces"))
    #expect(!paths.applicationSupportDirectory.path.contains("ConnorGraphAgent"))
}

@Test func appStoragePathsEnsureDirectoryHierarchyCreatesCommercialRuntimeFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-paths-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)

    let expectedDirectories = [
        paths.applicationSupportDirectory,
        paths.configDirectory,
        paths.sessionsDirectory,
        paths.sourcesDirectory,
        paths.skillsDirectory,
        paths.graphDirectory,
        paths.graphIndexesDirectory,
        paths.graphExportsDirectory,
        paths.graphSnapshotsDirectory,
        paths.logsDirectory,
        paths.auditLogsDirectory,
        paths.runtimeLogsDirectory,
        paths.sidecarsDirectory
    ]

    for directory in expectedDirectories {
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
