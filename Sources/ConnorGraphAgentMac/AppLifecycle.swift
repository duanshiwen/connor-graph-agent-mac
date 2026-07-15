import Foundation

@MainActor
final class AppLifecycle: ObservableObject {
    typealias SynchronousAction = @MainActor () -> Void
    typealias AsynchronousAction = @MainActor () async -> Void

    private let startTaskScheduler: SynchronousAction
    private let recoverNoteImports: AsynchronousAction
    private let restoreIdentitySession: AsynchronousAction
    private let shutdownRuntimeResources: SynchronousAction

    private var startupTask: Task<Void, Never>?
    private(set) var hasStarted = false
    private(set) var hasFinishedStarting = false
    private(set) var isShutdown = false

    init(
        startTaskScheduler: @escaping SynchronousAction,
        recoverNoteImports: @escaping AsynchronousAction,
        restoreIdentitySession: @escaping AsynchronousAction,
        shutdownRuntimeResources: @escaping SynchronousAction
    ) {
        self.startTaskScheduler = startTaskScheduler
        self.recoverNoteImports = recoverNoteImports
        self.restoreIdentitySession = restoreIdentitySession
        self.shutdownRuntimeResources = shutdownRuntimeResources
    }

    func startIfNeeded() async {
        guard !isShutdown else { return }
        if let startupTask {
            await startupTask.value
            return
        }

        hasStarted = true
        let startTaskScheduler = self.startTaskScheduler
        let recoverNoteImports = self.recoverNoteImports
        let restoreIdentitySession = self.restoreIdentitySession
        let task = Task { @MainActor in
            AppStartupPerformance.event("RootViewTaskStarted")
            guard !Task.isCancelled else { return }
            startTaskScheduler()
            guard !Task.isCancelled else { return }
            await AppStartupPerformance.measure("NoteImportRecovery") {
                await recoverNoteImports()
            }
            guard !Task.isCancelled else { return }
            await AppStartupPerformance.measure("IdentityRestore") {
                await restoreIdentitySession()
            }
            guard !Task.isCancelled else { return }
            AppStartupPerformance.event("InitialRootTasksCompleted")
            self.hasFinishedStarting = true
        }
        startupTask = task
        await task.value
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        startupTask?.cancel()
        startupTask = nil
        shutdownRuntimeResources()
    }
}
