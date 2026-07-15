import Foundation
import Observation
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class ChatBackgroundTaskCoordinator {
    private let model: ChatSessionListModel
    private let repository: AppChatSessionRepository?
    private let titleWorker = ChatSessionTitleGenerationWorker()
    private var titleTasksBySessionID: [String: Task<Void, Never>] = [:]
    private var generation = 0

    @ObservationIgnored var generateTitle: ([String], String) async throws -> String = { _, _ in "新对话" }
    @ObservationIgnored var onSessionRenamed: (AgentSession) -> Void = { _ in }
    @ObservationIgnored var onRequestListRefresh: (String) -> Void = { _ in }
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(model: ChatSessionListModel, repository: AppChatSessionRepository?) {
        self.model = model
        self.repository = repository
    }

    func tasks(for sessionID: String?) -> [AppSessionBackgroundTask] {
        guard let sessionID else { return [] }
        return model.backgroundTasksBySessionID[sessionID, default: []].sorted { $0.createdAt > $1.createdAt }
    }

    func hasRunningTask(sessionID: String) -> Bool {
        model.backgroundTasksBySessionID[sessionID, default: []].contains { $0.status == .queued || $0.status == .running }
    }

    func runningTasksForDeletionCheck(sessionID: String) throws -> [AppSessionBackgroundTask] {
        let persisted = try repository?.loadBackgroundTasks(sessionID: sessionID).map(AppSessionBackgroundTask.init(persisted:)) ?? []
        let memory = model.backgroundTasksBySessionID[sessionID, default: []]
        var unique: [String: AppSessionBackgroundTask] = [:]
        for task in persisted + memory where task.status == .queued || task.status == .running { unique[task.id] = task }
        return Array(unique.values)
    }

    func load(sessionID: String) throws {
        guard let repository else { return }
        let activeIDs = Set(model.backgroundTasksBySessionID[sessionID, default: []]
            .filter { $0.status == .queued || $0.status == .running }.map(\.id))
        var tasks = try repository.loadBackgroundTasks(sessionID: sessionID).map(AppSessionBackgroundTask.init(persisted:))
        var interrupted = false
        for index in tasks.indices where (tasks[index].status == .queued || tasks[index].status == .running) && !activeIDs.contains(tasks[index].id) {
            tasks[index].status = .interrupted
            tasks[index].updatedAt = Date()
            tasks[index].errorMessage = "应用重启或会话恢复后，旧后台任务不会自动继续执行。"
            interrupted = true
            try repository.saveBackgroundTask(tasks[index].persisted)
        }
        model.backgroundTasksBySessionID[sessionID] = tasks
        if interrupted || !hasRunningTitleTask(sessionID: sessionID) { model.regeneratingTitleSessionIDs.remove(sessionID) }
    }

    func install(_ tasks: [AppSessionBackgroundTask], sessionID: String) {
        model.backgroundTasksBySessionID[sessionID] = tasks
        if !hasRunningTitleTask(sessionID: sessionID) { model.regeneratingTitleSessionIDs.remove(sessionID) }
    }

    func upsert(_ task: AppSessionBackgroundTask) {
        var tasks = model.backgroundTasksBySessionID[task.sessionID, default: []]
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        model.backgroundTasksBySessionID[task.sessionID] = tasks
        persist(task)
        if !hasRunningTitleTask(sessionID: task.sessionID) { model.regeneratingTitleSessionIDs.remove(task.sessionID) }
    }

    func removeSession(_ sessionID: String) {
        titleTasksBySessionID.removeValue(forKey: sessionID)?.cancel()
        model.backgroundTasksBySessionID.removeValue(forKey: sessionID)
        model.regeneratingTitleSessionIDs.remove(sessionID)
    }

    func regenerateTitle(sessionID: String) {
        guard !hasRunningTitleTask(sessionID: sessionID), titleTasksBySessionID[sessionID] == nil else { return }
        let task = enqueue(sessionID: sessionID, title: "重新生成会话标题", detail: "根据此会话中的所有用户 Prompt 生成 20 字以内标题。", kind: "title_generation")
        update(sessionID: sessionID, taskID: task.id, status: .running)
        let currentGeneration = generation
        titleTasksBySessionID[sessionID] = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == currentGeneration { self.titleTasksBySessionID.removeValue(forKey: sessionID) } }
            do {
                guard let repository = self.repository else { return }
                let prompts = try await self.titleWorker.userPrompts(repository: repository, sessionID: sessionID)
                try Task.checkCancellation()
                let title: String
                let detail: String
                if prompts.isEmpty {
                    title = "新对话"
                    detail = "没有用户 Prompt，已使用默认标题。"
                } else {
                    title = try await self.generateTitle(prompts, sessionID)
                    try Task.checkCancellation()
                    detail = "已更新为：\(title)"
                }
                let updated = try await self.titleWorker.renameSession(repository: repository, sessionID: sessionID, title: title)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.onSessionRenamed(updated)
                self.onRequestListRefresh("titleGenerationCompleted")
                self.update(sessionID: sessionID, taskID: task.id, status: .succeeded, detail: detail)
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == currentGeneration else { return }
                let message = String(describing: error)
                self.update(sessionID: sessionID, taskID: task.id, status: .failed, errorMessage: message)
                self.onError(message)
            }
        }
    }

    private func hasRunningTitleTask(sessionID: String) -> Bool {
        model.backgroundTasksBySessionID[sessionID, default: []].contains {
            $0.kind == "title_generation" && ($0.status == .queued || $0.status == .running)
        }
    }

    @discardableResult
    private func enqueue(sessionID: String, title: String, detail: String, kind: String) -> AppSessionBackgroundTask {
        let task = AppSessionBackgroundTask(sessionID: sessionID, kind: kind, title: title, detail: detail)
        model.backgroundTasksBySessionID[sessionID, default: []].append(task)
        persist(task)
        if kind == "title_generation" { model.regeneratingTitleSessionIDs.insert(sessionID) }
        return task
    }

    private func update(sessionID: String, taskID: String, status: AppSessionBackgroundTaskStatus, detail: String? = nil, errorMessage: String? = nil) {
        guard var tasks = model.backgroundTasksBySessionID[sessionID], let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        if let detail { tasks[index].detail = detail }
        tasks[index].errorMessage = errorMessage
        model.backgroundTasksBySessionID[sessionID] = tasks
        persist(tasks[index])
        if !hasRunningTitleTask(sessionID: sessionID) { model.regeneratingTitleSessionIDs.remove(sessionID) }
    }

    private func persist(_ task: AppSessionBackgroundTask) {
        do { try repository?.saveBackgroundTask(task.persisted) }
        catch { onError(String(describing: error)) }
    }

    func shutdown() {
        generation += 1
        for task in titleTasksBySessionID.values { task.cancel() }
        titleTasksBySessionID.removeAll()
    }
}
