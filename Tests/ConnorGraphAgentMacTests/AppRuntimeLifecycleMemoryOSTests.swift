import AppKit
import Foundation
import Testing
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Test func runtimeInitializesMemoryOSBackendWithoutDashboardRoute() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-app-vm-memory-os-cutover-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)
    let repository = try AppGraphRepository.bootstrap(paths: paths)

    let runtime = AppRuntimeLifecycle(
        entities: [],
        statements: [],
        observeLogEntries: [],
        repository: repository,
        databasePath: paths.databaseURL.path,
        storagePaths: paths
    )

    #expect(runtime.hasMemoryOSBackendForTests)
    #expect(!SidebarItem.allCases.map(\.rawValue).contains("Memory OS"))
}
