import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
final class RuntimeSettingsPersistenceCoordinator {
    enum Event { case loaded(AgentRuntimeSettings); case saved(AgentRuntimeSettings); case failed(String) }
    private let repository: AppRuntimeSettingsRepository?
    private var autosaveTask: Task<Void, Never>?
    private var cachedSettings: AgentRuntimeSettings = .default
    private var generation: UInt64 = 0
    private var isShutdown = false
    var onEvent: ((Event) -> Void)?

    init(repository: AppRuntimeSettingsRepository?) { self.repository = repository }

    func load() -> AgentRuntimeSettings? {
        guard !isShutdown else { return nil }
        do {
            let settings = try repository?.loadOrCreateDefault() ?? .default
            cachedSettings = settings
            onEvent?(.loaded(settings)); return settings
        } catch { onEvent?(.failed(String(describing: error))); return nil }
    }

    func save(snapshot: AgentRuntimeSettings) {
        guard !isShutdown else { return }
        do { try repository?.save(snapshot); cachedSettings = snapshot; onEvent?(.saved(snapshot)) }
        catch { onEvent?(.failed(String(describing: error))) }
    }

    func installLoadedSnapshot(_ settings: AgentRuntimeSettings) {
        guard !isShutdown else { return }
        cachedSettings = settings
    }

    func baseSnapshot() -> AgentRuntimeSettings { cachedSettings }

    func scheduleAutosave(snapshot: @escaping @MainActor () -> AgentRuntimeSettings) {
        guard !isShutdown else { return }
        generation &+= 1; let current = generation
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.isShutdown, self.generation == current else { return }
            self.autosaveTask = nil
            self.save(snapshot: snapshot())
        }
    }

    func reset() -> AgentRuntimeSettings? {
        guard !isShutdown else { return nil }
        let settings = AgentRuntimeSettings.default
        cachedSettings = settings
        save(snapshot: settings)
        return settings
    }

    func shutdown() { guard !isShutdown else { return }; isShutdown = true; generation &+= 1; autosaveTask?.cancel(); autosaveTask = nil }
}
