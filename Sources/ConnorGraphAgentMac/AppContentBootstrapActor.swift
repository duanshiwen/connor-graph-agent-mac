import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

struct StartupDomainResult<Value: Sendable>: Sendable {
    let value: Value?
    let failureMessage: String?

    static func success(_ value: Value) -> Self {
        Self(value: value, failureMessage: nil)
    }

    static func failure(_ error: Error) -> Self {
        Self(value: nil, failureMessage: String(describing: error))
    }
}

struct ProductOSContentSnapshot: Sendable {
    let registry: ProductOSRegistrySnapshot
    let automationConfig: ProductOSAutomationConfig
    let triggerRecords: [ProductOSAutomationTriggerRecord]
    let executionHistory: [ProductOSAutomationExecutionHistoryRecord]
}

struct SourceRuntimeContentSnapshot: Sendable {
    let configurations: [MCPSourceRuntimeConfiguration]
    let healthRecords: [MCPSourceRuntimeHealthRecord]
    let toolCatalogs: [String: [MCPSourceToolDescriptor]]
    let auditRecordsBySource: [String: [MCPSourceRuntimeAuditRecord]]
}

struct AppContentBootstrapSnapshot: Sendable {
    let productOS: StartupDomainResult<ProductOSContentSnapshot>
    let tasks: StartupDomainResult<TaskManagementUIPresentation>
    let sources: StartupDomainResult<SourceRuntimeContentSnapshot>
    let skills: StartupDomainResult<[SkillRuntimeDefinition]>
    let browserHistory: StartupDomainResult<[BrowserHistoryRecord]>
}

actor AppContentBootstrapActor {
    func load(paths: AppStoragePaths, governanceConfig: AppSessionGovernanceConfig) async -> AppContentBootstrapSnapshot {
        async let productOS = Self.loadProductOS(paths: paths, governanceConfig: governanceConfig)
        async let tasks = Self.loadTasks(paths: paths)
        async let sources = Self.loadSources(paths: paths)
        async let skills = Self.loadSkills(paths: paths)
        async let browserHistory = Self.loadBrowserHistory(paths: paths)
        return await AppContentBootstrapSnapshot(
            productOS: productOS,
            tasks: tasks,
            sources: sources,
            skills: skills,
            browserHistory: browserHistory
        )
    }

    private nonisolated static func loadProductOS(
        paths: AppStoragePaths,
        governanceConfig: AppSessionGovernanceConfig
    ) -> StartupDomainResult<ProductOSContentSnapshot> {
        do {
            let registryRepository = AppProductOSRegistryRepository(storagePaths: paths)
            let automationRepository = AppProductOSAutomationRepository(storagePaths: paths)
            return .success(ProductOSContentSnapshot(
                registry: try registryRepository.loadOrCreateDefault(),
                automationConfig: try automationRepository.loadOrCreateDefault(governanceConfig: governanceConfig),
                triggerRecords: try automationRepository.loadRecentTriggerRecords(),
                executionHistory: try automationRepository.loadRecentExecutionHistory()
            ))
        } catch { return .failure(error) }
    }

    private nonisolated static func loadTasks(paths: AppStoragePaths) -> StartupDomainResult<TaskManagementUIPresentation> {
        do {
            let repository = AppTaskManagementRepository(storagePaths: paths)
            let tasks = try repository.loadOrCreateDefault()
            let history = try repository.loadRunHistory(taskID: nil, limit: 100)
            return .success(TaskManagementUIPresentation.build(tasks: tasks, runHistory: history))
        } catch { return .failure(error) }
    }

    private nonisolated static func loadSources(paths: AppStoragePaths) -> StartupDomainResult<SourceRuntimeContentSnapshot> {
        do {
            let repository = AppMCPSourceRuntimeRepository(storagePaths: paths)
            let configurations = try repository.list()
            var catalogs: [String: [MCPSourceToolDescriptor]] = [:]
            var audits: [String: [MCPSourceRuntimeAuditRecord]] = [:]
            for configuration in configurations {
                catalogs[configuration.sourceID] = try repository.loadToolCatalog(sourceID: configuration.sourceID)
                audits[configuration.sourceID] = try repository.loadRecentAuditRecords(sourceID: configuration.sourceID, limit: 12)
            }
            return .success(SourceRuntimeContentSnapshot(
                configurations: configurations,
                healthRecords: try repository.listHealthRecords(),
                toolCatalogs: catalogs,
                auditRecordsBySource: audits
            ))
        } catch { return .failure(error) }
    }

    private nonisolated static func loadSkills(paths: AppStoragePaths) -> StartupDomainResult<[SkillRuntimeDefinition]> {
        do { return .success(try AppSkillRuntimeRepository(storagePaths: paths).list()) }
        catch { return .failure(error) }
    }

    private nonisolated static func loadBrowserHistory(paths: AppStoragePaths) -> StartupDomainResult<[BrowserHistoryRecord]> {
        .success(BrowserHistoryStore(historyURL: paths.browserHistoryURL).loadHistory())
    }
}
