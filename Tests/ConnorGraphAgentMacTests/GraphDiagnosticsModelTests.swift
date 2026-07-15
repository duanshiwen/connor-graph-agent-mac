import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct GraphDiagnosticsModelTests {
    @Test func preservesInitialSnapshotAndDatabasePresentation() {
        let entity = GraphEntity(
            id: "entity-initial",
            graphID: "default",
            name: "Initial entity",
            stableKey: "project:entity:initial",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "concept"
        )
        let episode = GraphEpisodeV3(
            id: "episode-initial",
            graphID: "default",
            sourceType: .system,
            title: "Initial episode",
            content: "Initial content",
            sourceDescription: "Test fixture"
        )
        let entry = ObserveLogEntry(
            id: "observe-initial",
            kind: .insight,
            source: .agent,
            content: "Initial insight"
        )

        let model = GraphDiagnosticsModel(
            entities: [entity],
            statements: [],
            episodes: [episode],
            observeLogEntries: [entry],
            databasePath: "/tmp/graph.sqlite",
            repository: nil
        )

        #expect(model.entities == [entity])
        #expect(model.episodes == [episode])
        #expect(model.observeLogEntries == [entry])
        #expect(model.databasePath == "/tmp/graph.sqlite")
        #expect(model.query == "记忆")
    }

    @Test func unavailableRepositoryPreservesSearchAndSchemaFallbackBehavior() async {
        let model = GraphDiagnosticsModel(
            entities: [],
            statements: [],
            episodes: [],
            observeLogEntries: [],
            databasePath: nil,
            repository: nil
        )

        await model.runSearch()
        model.reloadSchemaHealthReport()

        #expect(model.searchResults.isEmpty)
        #expect(model.errorMessage == "SQLite hybrid search is unavailable.")
        #expect(model.schemaHealthReport == nil)
    }

    @Test func promotionAppliesReloadedSnapshotAndNotifiesOrchestrator() throws {
        let fixture = try makeRepositoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = GraphEntity(
            id: "entity-source",
            graphID: "default",
            name: "Source",
            stableKey: "project:entity:source",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "concept"
        )
        let target = GraphEntity(
            id: "entity-target",
            graphID: "default",
            name: "Target",
            stableKey: "project:entity:target",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "concept"
        )
        try fixture.repository.store.upsert(entity: source)
        try fixture.repository.store.upsert(entity: target)

        let model = GraphDiagnosticsModel(
            entities: [],
            statements: [],
            episodes: [],
            observeLogEntries: [],
            databasePath: fixture.paths.databaseURL.path,
            repository: fixture.repository
        )
        var notifiedSnapshot: GraphStoreSnapshot?
        model.onPromotedSnapshot = { notifiedSnapshot = $0 }
        let entry = ObserveLogEntry(
            id: "observe-promote",
            kind: .candidateFact,
            source: .agent,
            content: "Source is related to Target",
            relatedNodeIDs: [source.id, target.id]
        )

        model.promote(entry)

        #expect(model.statements.contains { $0.id == "statement-promoted-observe-promote" })
        #expect(notifiedSnapshot?.statements.contains { $0.id == "statement-promoted-observe-promote" } == true)
        #expect(model.lastPromotionResultSummary == "已提升 observe-promote：0 个节点，1 条事实")
        #expect(model.errorMessage == nil)
    }

    private func makeRepositoryFixture() throws -> (root: URL, paths: AppStoragePaths, repository: AppGraphRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-graph-diagnostics-model-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        return (root, paths, try AppGraphRepository.bootstrap(paths: paths))
    }
}
