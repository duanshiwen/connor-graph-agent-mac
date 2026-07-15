import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphStore
import ConnorGraphAppSupport

struct CoreBootstrapSnapshot: @unchecked Sendable {
    let paths: AppStoragePaths
    let repository: AppGraphRepository
    let graphSnapshot: GraphStoreSnapshot
    let governanceConfig: AppSessionGovernanceConfig
    let productOSRegistry: ProductOSRegistrySnapshot
    let automationConfig: ProductOSAutomationConfig
    let contactsProfileStore: SQLitePersonProfileStore?
    let contactsRelationshipStore: SQLitePersonRelationshipStore?
    let nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
    let sessionSearchIndexService: SessionSearchIndexService?
    let mailStore: FileBackedMailSourceStore?
    let memoryOSStore: SQLiteMemoryOSStore?
    let memoryOSFacade: AppMemoryOSFacade?
    let memoryOSSearchHealthSummary: String?
    let memoryOSInitializationError: String?
}

actor AppBootstrapActor {
    func loadCore() throws -> CoreBootstrapSnapshot {
        let paths = try AppStoragePaths.live()
        let repository = try AppGraphRepository.bootstrap(paths: paths)
        let governanceConfig = try AppSessionGovernanceConfigRepository(configDirectory: paths.configDirectory).loadOrCreateDefault()
        let productOSRegistry = try AppProductOSRegistryRepository(storagePaths: paths).loadOrCreateDefault()
        let automationConfig = try AppProductOSAutomationRepository(storagePaths: paths).loadOrCreateDefault(governanceConfig: governanceConfig)

        var graphSnapshot = try repository.loadSnapshot()
        if graphSnapshot.entities.isEmpty {
            let demo = AppDemoGraphSnapshotFactory.make()
            for entity in demo.entities { try repository.store.upsert(entity: entity) }
            for statement in demo.statements { try repository.store.upsert(statement: statement) }
            for episode in demo.episodes { try repository.store.upsert(episode: episode) }
            graphSnapshot = try repository.loadSnapshot()
        }

        let contactsDatabaseURL = paths.applicationSupportDirectory
            .appendingPathComponent("contacts", isDirectory: true)
            .appendingPathComponent("person-profiles.sqlite")
        let contactsProfileStore = try? SQLitePersonProfileStore(databaseURL: contactsDatabaseURL)
        let contactsRelationshipStore = try? SQLitePersonRelationshipStore(databaseURL: contactsDatabaseURL)

        let nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
        if let sqliteBackend = try? SQLiteNativeSourceSearchBackend(databaseURL: paths.nativeSourceSearchDatabaseURL) {
            nativeSourceSearchBackend = sqliteBackend
        } else {
            nativeSourceSearchBackend = NativeSourceSearchService(storagePaths: paths)
        }
        let sessionSearchIndexService = try? SessionSearchIndexService(databaseURL: paths.sessionSearchDatabaseURL)
        let mailStore = try? FileBackedMailSourceStore(openingStoragePaths: paths, searchService: nativeSourceSearchBackend)

        var memoryOSStore: SQLiteMemoryOSStore?
        var memoryOSFacade: AppMemoryOSFacade?
        var memoryOSSearchHealthSummary: String?
        var memoryOSInitializationError: String?
        do {
            let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
            try store.migrate()
            let health = AppMemoryOSSearchKernelFactory.healthReport(paths: paths)
            let searchKernel = try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: paths)
            memoryOSStore = store
            memoryOSFacade = AppMemoryOSFacade(store: store, searchKernel: searchKernel)
            memoryOSSearchHealthSummary = health.status == .healthy
                ? "Memory OS SearchKernel 正常：索引已验证。"
                : "Memory OS SearchKernel 降级启动，后台将修复索引：\(health.messages.joined(separator: ", "))"
        } catch {
            memoryOSInitializationError = "Memory OS 初始化失败：\(error)"
        }

        return CoreBootstrapSnapshot(
            paths: paths,
            repository: repository,
            graphSnapshot: graphSnapshot,
            governanceConfig: governanceConfig,
            productOSRegistry: productOSRegistry,
            automationConfig: automationConfig,
            contactsProfileStore: contactsProfileStore,
            contactsRelationshipStore: contactsRelationshipStore,
            nativeSourceSearchBackend: nativeSourceSearchBackend,
            sessionSearchIndexService: sessionSearchIndexService,
            mailStore: mailStore,
            memoryOSStore: memoryOSStore,
            memoryOSFacade: memoryOSFacade,
            memoryOSSearchHealthSummary: memoryOSSearchHealthSummary,
            memoryOSInitializationError: memoryOSInitializationError
        )
    }
}
