import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppMaintenanceBootstrapSnapshot: Sendable {
    let tasks: StartupDomainResult<TaskManagementUIPresentation>
    let promotionCandidates: StartupDomainResult<[ObserveLogEntry]>
    let schemaHealth: StartupDomainResult<GraphSchemaHealthReport>
    let pendingApprovals: StartupDomainResult<[AgentPendingApproval]>
}

actor AppMaintenanceBootstrapActor {
    func load(paths: AppStoragePaths, repository: AppGraphRepository) async -> AppMaintenanceBootstrapSnapshot {
        async let tasks = Self.loadTasks(paths: paths)
        async let promotionCandidates = Self.loadPromotionCandidates(repository: repository)
        async let schemaHealth = Self.loadSchemaHealth(repository: repository)
        async let pendingApprovals = Self.loadPendingApprovals(repository: repository)
        return await AppMaintenanceBootstrapSnapshot(
            tasks: tasks,
            promotionCandidates: promotionCandidates,
            schemaHealth: schemaHealth,
            pendingApprovals: pendingApprovals
        )
    }

    private nonisolated static func loadTasks(paths: AppStoragePaths) -> StartupDomainResult<TaskManagementUIPresentation> {
        do {
            let taskRepository = AppTaskManagementRepository(storagePaths: paths)
            let tasks = try taskRepository.loadOrCreateDefault()
            let history = try taskRepository.loadRunHistory(taskID: nil, limit: 100)
            return .success(TaskManagementUIPresentation.build(tasks: tasks, runHistory: history))
        } catch { return .failure(error) }
    }

    private nonisolated static func loadPromotionCandidates(repository: AppGraphRepository) -> StartupDomainResult<[ObserveLogEntry]> {
        do { return .success(try AppPromotionQueueRepository(store: repository.store).loadCandidates()) }
        catch { return .failure(error) }
    }

    private nonisolated static func loadSchemaHealth(repository: AppGraphRepository) -> StartupDomainResult<GraphSchemaHealthReport> {
        do { return .success(try repository.store.schemaHealthReport()) }
        catch { return .failure(error) }
    }

    private nonisolated static func loadPendingApprovals(repository: AppGraphRepository) -> StartupDomainResult<[AgentPendingApproval]> {
        do { return .success(try AppAgentPendingApprovalRepository(store: repository.store).loadPending()) }
        catch { return .failure(error) }
    }
}
