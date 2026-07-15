import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import ConnorGraphAppSupport
import ConnorGraphSearch

enum MaintenanceReconcileScope: Hashable, Sendable {
    case allSources
    case rss
    case calendar
    case mail
}

@MainActor
@Observable
final class AppMaintenanceCoordinator {
    private var applicationDidFinishLaunchingObserver: NSObjectProtocol?
    private var schedulerTimer: Timer?
    private var schedulerTask: Task<Void, Never>?
    private var isSchedulerRunning = false
    private var schedulerGeneration = 0
    private var backgroundJobsTask: Task<Void, Never>?
    private var dailySweepTask: Task<Void, Never>?
    private var repairTask: Task<Void, Never>?
    private var reconcileTasks: [MaintenanceReconcileScope: Task<Void, Error>] = [:]
    private var idleSleepAssertionID = IOPMAssertionID(0)
    private var generation = 0
    private var isShutdown = false
    private var isRunningBackgroundJobs = false
    private var lastDailySweep: Date?
    private var hasScheduledRepair = false
    private let memoryWorker = AppMemoryOSMaintenanceWorker()
#if DEBUG
    private let stallMonitor = AppMainActorStallMonitor()
#endif

    @ObservationIgnored var runScheduledTasks: () async -> Void = {}
    @ObservationIgnored var runBackgroundJobs: () async -> Void = {}
    @ObservationIgnored var runDailySweep: () async -> Void = {}
    @ObservationIgnored var onApplicationDidFinishLaunching: () -> Void = {}
    @ObservationIgnored var reconcileSources: (MaintenanceReconcileScope) async throws -> Void = { _ in }

    func startObservers() {
        guard !isShutdown else { return }
#if DEBUG
        stallMonitor.start()
#endif
        guard applicationDidFinishLaunchingObserver == nil else { return }
        applicationDidFinishLaunchingObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isShutdown else { return }
                self.onApplicationDidFinishLaunching()
            }
        }
    }

    func startScheduler(interval: TimeInterval = 60) {
        guard !isShutdown, schedulerTimer == nil else { return }
        isSchedulerRunning = true
        runScheduledTasksOnce()
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runScheduledTasksOnce() }
        }
    }

    func stopScheduler() {
        schedulerGeneration += 1
        isSchedulerRunning = false
        schedulerTimer?.invalidate()
        schedulerTimer = nil
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    func runScheduledTasksOnce() {
        guard !isShutdown, isSchedulerRunning, schedulerTask == nil else { return }
        let currentGeneration = generation
        let currentSchedulerGeneration = schedulerGeneration
        schedulerTask = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.isSchedulerRunning,
                  self.generation == currentGeneration,
                  self.schedulerGeneration == currentSchedulerGeneration else { return }
            await self.runScheduledTasks()
            guard self.generation == currentGeneration,
                  self.schedulerGeneration == currentSchedulerGeneration else { return }
            self.schedulerTask = nil
        }
    }

    func reconcile(_ scope: MaintenanceReconcileScope) async throws {
        guard !isShutdown else { throw CancellationError() }
        if let task = reconcileTasks[scope] { return try await task.value }
        let currentGeneration = generation
        let operation = reconcileSources
        let task = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.generation == currentGeneration,
                  !self.isShutdown else { throw CancellationError() }
            try await operation(scope)
        }
        reconcileTasks[scope] = task
        defer { if generation == currentGeneration { reconcileTasks.removeValue(forKey: scope) } }
        try await task.value
        try Task.checkCancellation()
        guard generation == currentGeneration, !isShutdown else { throw CancellationError() }
    }

    func scheduleBackgroundJobs() {
        guard !isShutdown, backgroundJobsTask == nil else { return }
        let currentGeneration = generation
        backgroundJobsTask = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.generation == currentGeneration else { return }
            await self.runBackgroundJobs()
            guard self.generation == currentGeneration else { return }
            self.backgroundJobsTask = nil
        }
    }

    func scheduleDailySweep() {
        guard !isShutdown, dailySweepTask == nil else { return }
        let currentGeneration = generation
        dailySweepTask = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.generation == currentGeneration else { return }
            await self.runDailySweep()
            guard self.generation == currentGeneration else { return }
            self.dailySweepTask = nil
        }
    }

    func runMemoryBackgroundJobs(
        facade: AppMemoryOSFacade?,
        aiExecutorProvider: BackgroundAIExecutorProvider?,
        onError: @escaping (String) -> Void
    ) async {
        guard !isShutdown, !isRunningBackgroundJobs, let facade else { return }
        isRunningBackgroundJobs = true
        defer { isRunningBackgroundJobs = false }
        do {
            let startedAt = ContinuousClock.now
            let summary = try await memoryWorker.runBackgroundJobs(
                facade: facade,
                aiExecutorProvider: aiExecutorProvider,
                now: Date()
            )
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info(
                "memoryOS.backgroundJobs.completed projectionRuns=\(summary.projectionRunCount, privacy: .public) aiRuns=\(summary.aiJobRunCount, privacy: .public) duration=\(milliseconds, privacy: .public)ms"
            )
        } catch {
            guard !isShutdown else { return }
            onError(String(describing: error))
        }
    }

    func runMemoryDailySweep(facade: AppMemoryOSFacade?, now: Date = Date()) async {
        guard !isShutdown, let facade else { return }
        guard lastDailySweep.map({ now.timeIntervalSince($0) > 86_400 }) ?? true else { return }
        lastDailySweep = now
        do {
            let startedAt = ContinuousClock.now
            let items = try await memoryWorker.runDailySweep(facade: facade, now: now)
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info(
                "memoryOS.dailySweep.completed queued=\(items.count, privacy: .public) duration=\(milliseconds, privacy: .public)ms"
            )
        } catch {
            AppPerformanceLog.chatTurnLogger.warning(
                "memoryOS.dailySweep.failed error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    func scheduleMemorySearchRepair(
        storagePaths: AppStoragePaths?,
        onStarted: @escaping @MainActor @Sendable (String) -> Void,
        onSucceeded: @escaping @MainActor @Sendable (Int, MemoryOSSearchKernel?) -> Void,
        onFailed: @escaping @MainActor @Sendable (String) -> Void
    ) {
        guard !isShutdown, !hasScheduledRepair, let storagePaths else { return }
        let report = AppMemoryOSSearchKernelFactory.healthReport(paths: storagePaths)
        guard report.status != .healthy else { return }
        hasScheduledRepair = true
        onStarted(report.messages.joined(separator: ", "))
        let currentGeneration = generation
        let task = Task.detached(priority: .utility) {
            do {
                let count = try AppMemoryOSSearchKernelFactory.rebuildLiveIndex(paths: storagePaths)
                let kernel = try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: storagePaths)
                await MainActor.run {
                    guard self.generation == currentGeneration, !self.isShutdown else { return }
                    onSucceeded(count, kernel)
                    self.repairTask = nil
                }
            } catch {
                await MainActor.run {
                    guard self.generation == currentGeneration, !self.isShutdown else { return }
                    onFailed(String(describing: error))
                    self.repairTask = nil
                }
            }
        }
        installRepairTask(task)
    }

    func installRepairTask(_ task: Task<Void, Never>) {
        guard !isShutdown else { task.cancel(); return }
        repairTask?.cancel()
        repairTask = task
    }

    func updateKeepScreenAwake(enabled: Bool, hasActiveRun: Bool) {
        guard !isShutdown else { return }
        if enabled && hasActiveRun {
            guard idleSleepAssertionID == 0 else { return }
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Connor session is running" as CFString,
                &assertionID
            )
            if result == kIOReturnSuccess { idleSleepAssertionID = assertionID }
        } else {
            releaseIdleSleepAssertion()
        }
    }

    private func releaseIdleSleepAssertion() {
        guard idleSleepAssertionID != 0 else { return }
        IOPMAssertionRelease(idleSleepAssertionID)
        idleSleepAssertionID = 0
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        generation += 1
        if let observer = applicationDidFinishLaunchingObserver {
            NotificationCenter.default.removeObserver(observer)
            applicationDidFinishLaunchingObserver = nil
        }
        stopScheduler()
        backgroundJobsTask?.cancel(); backgroundJobsTask = nil
        dailySweepTask?.cancel(); dailySweepTask = nil
        repairTask?.cancel(); repairTask = nil
        for task in reconcileTasks.values { task.cancel() }
        reconcileTasks.removeAll()
        releaseIdleSleepAssertion()
#if DEBUG
        stallMonitor.stop()
#endif
    }
}
