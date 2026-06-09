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
    #expect(tables.contains("graph_episodes"))
    #expect(tables.contains("graph_nodes_v2"))
    #expect(tables.contains("graph_facts"))
    #expect(tables.contains("observe_log_entries"))
}

@Test func appGraphRepositoryLoadsTemporalGraphSnapshotFromSQLiteStore() throws {
    let base = try temporaryDirectory()
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let question = GraphNodeV2(id: "question-memory", groupID: "default", type: .question, canonicalName: "How should memory work?", title: "How should memory work?")
    let answer = GraphNodeV2(id: "answer-runtime", groupID: "default", type: .answer, canonicalName: "Use SQLite", title: "Use SQLite")
    let fact = GraphFact(id: "fact-memory-runtime", groupID: "default", sourceNodeID: question.id, targetNodeID: answer.id, relation: .answeredBy, fact: "Memory question is answered by SQLite runtime")
    let episode = GraphEpisode(id: "episode-runtime", groupID: "default", sourceType: .manual, name: "Runtime graph", content: "SQLite is the runtime graph source of truth.", sourceDescription: "test")

    try repository.store.upsert(nodeV2: question)
    try repository.store.upsert(nodeV2: answer)
    try repository.store.upsert(fact: fact)
    try repository.store.upsert(episode: episode)

    let snapshot = try repository.loadSnapshot()

    #expect(snapshot.graphNodes.map(\.id).contains(question.id))
    #expect(snapshot.graphNodes.map(\.id).contains(answer.id))
    #expect(snapshot.graphFacts.map(\.id).contains(fact.id))
    #expect(snapshot.graphEpisodes.map(\.id).contains(episode.id))
}
