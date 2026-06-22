import AppKit
import Foundation
import Testing
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Test func sidebarItemsDoNotExposeMemoryOSAsUserVisibleRoute() {
    #expect(!SidebarItem.allCases.map(\.rawValue).contains("Memory OS"))
}

@MainActor
@Test func appViewModelKeepsMemoryOSBackendButGraphMemoryNavigationFallsBackToAgentChat() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-app-vm-memory-os-hidden-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)
    let repository = try AppGraphRepository.bootstrap(paths: paths)

    let viewModel = AppViewModel(
        entities: [],
        statements: [],
        observeLogEntries: [],
        repository: repository,
        databasePath: paths.databaseURL.path,
        storagePaths: paths
    )

    #expect(viewModel.hasMemoryOSBackendForTests)

    viewModel.navigate(to: .graphMemory)
    try await Task.sleep(nanoseconds: 30_000_000)

    #expect(viewModel.selection == .agentChat)
}
