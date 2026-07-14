import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@MainActor
extension AppViewModel {
static func live() -> AppViewModel {
    AppStartupPerformance.measure("SynchronousLiveBootstrap") {
        do {
            let paths = try AppStartupPerformance.measure("StoragePaths") {
                try AppStoragePaths.live()
            }
            let repository = try AppStartupPerformance.measure("GraphRepositoryBootstrap") {
                try AppGraphRepository.bootstrap(paths: paths)
            }
            let configurations = try AppStartupPerformance.measure("CoreConfigurationLoad") {
                let governanceConfig = try AppSessionGovernanceConfigRepository(configDirectory: paths.configDirectory).loadOrCreateDefault()
                let productOSRegistry = try AppProductOSRegistryRepository(storagePaths: paths).loadOrCreateDefault()
                let automationConfig = try AppProductOSAutomationRepository(storagePaths: paths).loadOrCreateDefault(governanceConfig: governanceConfig)
                return (governanceConfig, productOSRegistry, automationConfig)
            }
            var snapshot = try AppStartupPerformance.measure("GraphSnapshotLoad") {
                try repository.loadSnapshot()
            }
            if snapshot.entities.isEmpty {
                snapshot = try AppStartupPerformance.measure("DemoSeedPersistence") {
                    let demo = demoSnapshot()
                    for entity in demo.entities { try repository.store.upsert(entity: entity) }
                    for statement in demo.statements { try repository.store.upsert(statement: statement) }
                    for episode in demo.episodes { try repository.store.upsert(episode: episode) }
                    return try repository.loadSnapshot()
                }
            }
            let viewModel = AppStartupPerformance.measure("AppViewModelConstruction") {
                AppViewModel(
                    entities: snapshot.entities,
                    statements: snapshot.statements,
                    episodes: snapshot.episodes,
                    observeLogEntries: snapshot.observeLogEntries,
                    repository: repository,
                    databasePath: paths.databaseURL.path,
                    storagePaths: paths,
                    governanceConfig: configurations.0,
                    productOSRegistry: configurations.1,
                    automationConfig: configurations.2
                )
            }
            AppStartupPerformance.measure("InitialApprovalPresentation") {
                viewModel.graphDiagnosticsModel.reloadPromotionCandidates()
                viewModel.reloadPendingApprovals()
            }
            return viewModel
        } catch {
            let viewModel = AppViewModel.demo()
            viewModel.errorMessage = "已回退到演示数据：\(error)"
            return viewModel
        }
    }
}

static func demo() -> AppViewModel {
    let snapshot = demoSnapshot()
    return AppViewModel(entities: snapshot.entities, statements: snapshot.statements, episodes: snapshot.episodes, observeLogEntries: snapshot.observeLogEntries)
}

private static func demoSnapshot() -> GraphStoreSnapshot {
    let workObject = GraphEntity(
        id: "work-object-agent-os",
        graphID: "default",
        name: "康纳同学",
        stableKey: "project:work_object:agent-os",
        entityKind: .workObject,
        scope: .project,
        canonicalClassID: "project",
        summary: "A local-first operating system for graph-backed agents."
    )
    let question = GraphEntity(
        id: "question-memory",
        graphID: "default",
        name: "How should memory work?",
        stableKey: "project:entity:question-memory",
        entityKind: .entity,
        scope: .project,
        canonicalClassID: "question",
        summary: "Agent memory should be grounded in graph context."
    )
    let answer = GraphEntity(
        id: "answer-graph-memory",
        graphID: "default",
        name: "Use graph-backed context",
        stableKey: "project:entity:answer-graph-memory",
        entityKind: .entity,
        scope: .project,
        canonicalClassID: "answer",
        summary: "Use a local graph store as the runtime knowledge source of truth."
    )
    let fact = GraphStatement(
        id: "statement-question-memory-answered-by-answer-graph-memory",
        graphID: "default",
        subjectEntityID: question.id,
        predicate: .answeredBy,
        objectEntityID: answer.id,
        statementText: "question-memory is answered by answer-graph-memory",
        validAt: Date(timeIntervalSince1970: 1_700_000_000),
        justifications: [GraphJustification(type: .userStated, source: "demo", strength: 1.0)],
        sourceEpisodeIDs: ["episode-demo"]
    )
    let episode = GraphEpisodeV3(
        id: "episode-demo",
        graphID: "default",
        sourceType: .system,
        title: "Demo seed",
        content: "Graph store is runtime knowledge source of truth.",
        sourceDescription: "Built-in demo seed"
    )
    let observe = ObserveLogEntry(
        id: "observe-demo",
        kind: .insight,
        source: .agent,
        content: "Recent insight: graph store is the runtime knowledge layer.",
        normalizedSummary: "Graph store is runtime knowledge source of truth",
        workObjectID: workObject.id
    )
    return GraphStoreSnapshot(entities: [workObject, question, answer], statements: [fact], episodes: [episode], observeLogEntries: [observe])
}
}
