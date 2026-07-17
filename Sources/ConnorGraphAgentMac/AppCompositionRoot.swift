import Foundation
import ConnorGraphAppSupport

@MainActor
final class AppCompositionRoot: ObservableObject {
    @Published private(set) var graph: AppFeatureGraph
    @Published private(set) var noteImportModel: NoteImportViewModel
    let identityStore: AppUserIdentityStore
    let featureFlags: AppFeatureFlags
    let flowCoordinator: AppFlowCoordinator
    let commandRouter: AppCommandRouter
    private(set) var startupCoordinator: AppStartupCoordinator!

    private enum CoreOutcome {
        case loaded(CoreBootstrapSnapshot)
        case fallback(Error)
    }

    private let bootstrapActor: AppBootstrapActor
    private let interactiveBootstrapActor = AppInteractiveBootstrapActor()
    private let contentBootstrapActor = AppContentBootstrapActor()
    private let maintenanceBootstrapActor = AppMaintenanceBootstrapActor()
    private var runtime: AppRuntimeLifecycle
    private var coreOutcome: CoreOutcome?

    private init(
        runtime: AppRuntimeLifecycle,
        identityStore: AppUserIdentityStore,
        noteImportModel: NoteImportViewModel,
        featureFlags: AppFeatureFlags,
        bootstrapActor: AppBootstrapActor
    ) {
        self.runtime = runtime
        self.graph = runtime.graph
        self.identityStore = identityStore
        self.noteImportModel = noteImportModel
        self.featureFlags = featureFlags
        self.bootstrapActor = bootstrapActor
        self.flowCoordinator = AppFlowCoordinator { _ in }
        self.commandRouter = AppCommandRouter()
    }

    static func live() -> AppCompositionRoot {
        AppStartupPerformance.measure("StartupLightConstruction") {
            let backendBaseURL = URL(string: ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"] ?? "http://localhost:8080")!
            AppBackendConnectivity.shared.configure(baseURL: backendBaseURL)
            let placeholder = AppRuntimeLifecycle.placeholder()
            let root = AppCompositionRoot(
                runtime: placeholder,
                identityStore: AppUserIdentityStore(
                    baseURL: backendBaseURL,
                    transport: BackendConnectivityTrackingTransport(),
                    networkIsAvailable: { AppNetworkConnectivity.shared.isConnected },
                    serverIsReachable: { AppBackendConnectivity.shared.isReachable }
                ),
                noteImportModel: NoteImportViewModel(configurationError: "导入功能正在准备中…"),
                featureFlags: AppFeatureFlags.load(),
                bootstrapActor: AppBootstrapActor()
            )
            root.installStartupCoordinator()
            root.bindCommandRouting(to: placeholder)
            AppStartupPerformance.event("AppCompositionLightConstructed")
            return root
        }
    }

    func sendWhenInteractive(_ command: AppCommand) {
        startupCoordinator.performWhenInteractive { [weak self] in
            self?.commandRouter.send(command)
        }
    }

    private func installStartupCoordinator() {
        startupCoordinator = AppStartupCoordinator(
            coreBootstrap: { [weak self] generation in
                guard let self else { throw CancellationError() }
                let outcome: CoreOutcome
                do {
                    outcome = .loaded(try await self.bootstrapActor.loadCore())
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    outcome = .fallback(error)
                }
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                self.coreOutcome = outcome
            },
            prepareInteractive: { [weak self] generation in
                guard let self,
                      self.startupCoordinator.acceptsResults(for: generation),
                      let coreOutcome = self.coreOutcome
                else { throw CancellationError() }
                let runtime: AppRuntimeLifecycle
                let interactiveSnapshot: AppInteractiveBootstrapSnapshot?
                switch coreOutcome {
                case .loaded(let snapshot):
                    interactiveSnapshot = await self.interactiveBootstrapActor.load(
                        paths: snapshot.paths,
                        repository: snapshot.repository,
                        governanceConfig: snapshot.governanceConfig
                    )
                    guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                    runtime = AppRuntimeLifecycle.live(core: snapshot)
                case .fallback(let error):
                    interactiveSnapshot = nil
                    runtime = AppRuntimeLifecycle.demo(fallbackError: error)
                }
                self.bindCommandRouting(to: runtime)
                runtime.prepareInteractive(snapshot: interactiveSnapshot)
                let noteImportModel = runtime.makeNoteImportModel()
                guard self.startupCoordinator.acceptsResults(for: generation) else {
                    runtime.shutdown()
                    noteImportModel.stopJobMonitoring()
                    throw CancellationError()
                }
                let previousRuntime = self.runtime
                previousRuntime.shutdown()
                self.runtime = runtime
                self.graph = runtime.graph
                self.noteImportModel = noteImportModel
            },
            loadContent: { [weak self] generation in
                guard let self, self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                let snapshot: AppContentBootstrapSnapshot?
                switch self.coreOutcome {
                case .loaded(let core):
                    snapshot = await self.contentBootstrapActor.load(paths: core.paths, governanceConfig: core.governanceConfig)
                case .fallback, .none:
                    snapshot = nil
                }
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.runtime.loadContent(snapshot: snapshot)
            },
            startMaintenance: { [weak self] generation in
                guard let self, self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                self.runtime.startScheduler()
                await self.noteImportModel.recoverPersistedJobs()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.identityStore.restoreSession()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.runtime.reloadKnowledgeMarketplace()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.runtime.reconcileStartupRefreshTasks()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                let snapshot: AppMaintenanceBootstrapSnapshot?
                switch self.coreOutcome {
                case .loaded(let core):
                    snapshot = await self.maintenanceBootstrapActor.load(paths: core.paths, repository: core.repository)
                case .fallback, .none:
                    snapshot = nil
                }
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.runtime.startMaintenance(snapshot: snapshot)
            },
            shutdown: { [weak self] in
                guard let self else { return }
                self.noteImportModel.stopJobMonitoring()
                self.runtime.shutdown()
            }
        )
    }

    private func bindCommandRouting(to runtime: AppRuntimeLifecycle) {
        commandRouter.replaceHandler { [weak self] command in
            self?.runtime.perform(command)
        }
        flowCoordinator.replaceHandler { [weak self] intent in
            guard let self else { return }
            let command: AppCommand
            switch intent {
            case let .navigate(selection): command = .selectSidebar(selection)
            case let .openSessionNotification(sessionID): command = .openSessionNotification(sessionID)
            case .openCalendarSettings: command = .openCalendarSettings
            case let .followRSSItem(request): command = .followRSSItem(request)
            }
            self.sendWhenInteractive(command)
        }
        runtime.graph.rss.onFollowRequest = { [weak flowCoordinator] request in
            flowCoordinator?.send(.followRSSItem(request))
        }
        runtime.graph.calendar.onOpenSettingsRequest = { [weak flowCoordinator] in
            flowCoordinator?.send(.openCalendarSettings)
        }
    }
}
