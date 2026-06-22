import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Test func appViewModelDoesNotLoadLegacyGraphMemoryStateOnMemoryOSPath() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-app-vm-memory-os-cutover-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let legacyCandidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "legacy-run",
        proposedByToolCallID: "legacy-tool-call",
        rationale: "legacy candidate should not be loaded by the Memory OS app path",
        confidence: 0.8,
        payloadJSON: #"{"id":"legacy"}"#
    )
    try repository.store.upsertWriteCandidate(legacyCandidate)

    let viewModel = AppViewModel(
        entities: [],
        statements: [],
        observeLogEntries: [],
        repository: repository,
        databasePath: paths.databaseURL.path,
        storagePaths: paths
    )

    #expect(viewModel.memoryOSDashboardPresentation.layerRows.contains { $0.id == "l0" })
}
