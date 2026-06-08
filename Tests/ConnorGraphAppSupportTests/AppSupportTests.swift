import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("connor-app-support-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func appStoragePathsResolveDatabaseURLUnderApplicationSupportBase() throws {
    let base = try temporaryDirectory()

    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)

    #expect(paths.applicationSupportDirectory == base.appendingPathComponent("ConnorGraphAgent", isDirectory: true))
    #expect(paths.databaseURL == base.appendingPathComponent("ConnorGraphAgent", isDirectory: true).appendingPathComponent("connor-graph.sqlite"))
}

@Test func appGraphBootstrapperCreatesDirectoryAndMigratesDatabase() throws {
    let base = try temporaryDirectory()
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)
    let bootstrapper = AppGraphBootstrapper(paths: paths)

    let store = try bootstrapper.bootstrapStore()
    let tables = try store.tableNames()

    #expect(FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.path))
    #expect(FileManager.default.fileExists(atPath: paths.databaseURL.path))
    #expect(tables.contains("graph_nodes"))
    #expect(tables.contains("semantic_edges"))
    #expect(tables.contains("observe_log_entries"))
}

@Test func appGraphRepositoryLoadsSnapshotFromSQLiteStore() throws {
    let base = try temporaryDirectory()
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let node = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS", summary: "Graph-backed runtime")
    let answer = GraphNode.answer(id: "answer-runtime", title: "Use SQLite", summary: "Persist graph data locally")
    let edge = SemanticEdge.answeredBy(questionID: node.id, answerID: answer.id)

    try repository.store.upsert(node: node)
    try repository.store.upsert(node: answer)
    try repository.store.upsert(edge: edge)

    let snapshot = try repository.loadSnapshot()

    #expect(snapshot.nodes.map(\.id).contains(node.id))
    #expect(snapshot.nodes.map(\.id).contains(answer.id))
    #expect(snapshot.edges.map(\.id).contains(edge.id))
}

@Test func appGraphRepositoryImportsMarkdownDirectoryIntoSQLiteStore() throws {
    let base = try temporaryDirectory()
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let knowledgeRoot = try temporaryDirectory("knowledge-root")
    let markdown = """
    ---
    title: Runtime Graph Store
    category: internal/projects
    summary: The SwiftUI app should use SQLite as the runtime graph source of truth.
    tags:
    - graph-store
    related:
    - docs/app.md
    ---

    # Runtime Graph Store

    The app imports Markdown as a legacy source, then searches graph nodes from SQLite.
    """
    try markdown.write(to: knowledgeRoot.appendingPathComponent("runtime-graph-store.md"), atomically: true, encoding: .utf8)

    let report = try repository.importKnowledgeDirectory(knowledgeRoot)
    let snapshot = try repository.loadSnapshot()

    #expect(report.scannedFiles == 1)
    #expect(report.importedNodes > 0)
    #expect(snapshot.nodes.contains { $0.sourcePath == "runtime-graph-store.md" })
}
