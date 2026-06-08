import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphImport
import ConnorGraphStore

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeTemporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path
}

@Test func directoryImporterScansMarkdownAndWritesGraphStore() throws {
    let root = try makeTemporaryDirectory()
    let workObjectURL = root.appendingPathComponent("internal/work-objects/projects/agent-os.md")
    try FileManager.default.createDirectory(at: workObjectURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = """
    ---
    title: Agent OS
    summary: Local-first graph-backed agent system
    work_object_id: agent-os
    related:
      - internal/decisions/use-swiftui.md
    ---
    # Agent OS
    Runtime knowledge lives in the graph store.
    """
    try original.write(to: workObjectURL, atomically: true, encoding: .utf8)

    let decisionURL = root.appendingPathComponent("internal/decisions/use-swiftui.md")
    try FileManager.default.createDirectory(at: decisionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    ---
    title: Use SwiftUI
    ---
    Decision body.
    """.write(to: decisionURL, atomically: true, encoding: .utf8)

    let store = try SQLiteGraphStore(path: makeTemporaryDatabasePath())
    try store.migrate()

    let report = try LegacyKnowledgeDirectoryImporter(store: store).importDirectory(root)

    #expect(report.scannedFiles == 2)
    #expect(report.importedNodes == 2)
    #expect(report.importedEdges == 1)
    #expect(report.skippedFiles == 0)
    #expect(try store.node(id: "work-object-agent-os")?.type == .workObject)
    #expect(try store.node(id: "decision-use-swiftui")?.type == .decision)
    #expect(try store.neighborhoodEdges(nodeID: "work-object-agent-os").contains { $0.relation == .relatedTo })
    #expect(try String(contentsOf: workObjectURL, encoding: .utf8) == original)
}

@Test func directoryImporterReportsSkippedFilesAndWarnings() throws {
    let root = try makeTemporaryDirectory()
    let invalidURL = root.appendingPathComponent("broken.md")
    try "# Missing frontmatter".write(to: invalidURL, atomically: true, encoding: .utf8)

    let store = try SQLiteGraphStore(path: makeTemporaryDatabasePath())
    try store.migrate()

    let report = try LegacyKnowledgeDirectoryImporter(store: store).importDirectory(root)

    #expect(report.scannedFiles == 1)
    #expect(report.importedNodes == 0)
    #expect(report.skippedFiles == 1)
    #expect(report.warnings.count == 1)
    #expect(report.warnings[0].path.hasSuffix("broken.md"))
}

@Test func realIntelligenceRepositoryReadOnlyImportSmoke() throws {
    guard let path = ProcessInfo.processInfo.environment["CONNOR_REAL_REPO_IMPORT_PATH"], !path.isEmpty else {
        return
    }
    let root = URL(fileURLWithPath: path, isDirectory: true)
    let store = try SQLiteGraphStore(path: makeTemporaryDatabasePath())
    try store.migrate()

    let report = try LegacyKnowledgeDirectoryImporter(store: store).importDirectory(root)

    #expect(report.scannedFiles > 0)
    #expect(report.importedNodes > 0)
    #expect(report.importedNodes + report.skippedFiles == report.scannedFiles)
}
