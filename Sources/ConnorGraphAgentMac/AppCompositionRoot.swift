import Foundation
import ConnorGraphAppSupport

@MainActor
final class AppCompositionRoot: ObservableObject {
    @Published private(set) var viewModel: AppViewModel
    @Published private(set) var noteImportModel: NoteImportViewModel
    let identityStore: AppUserIdentityStore
    let featureFlags: AppFeatureFlags
    let flowCoordinator: AppFlowCoordinator
    private(set) var startupCoordinator: AppStartupCoordinator!

    private enum CoreOutcome {
        case loaded(CoreBootstrapSnapshot)
        case fallback(Error)
    }

    private let bootstrapActor: AppBootstrapActor
    private let interactiveBootstrapActor = AppInteractiveBootstrapActor()
    private let contentBootstrapActor = AppContentBootstrapActor()
    private let maintenanceBootstrapActor = AppMaintenanceBootstrapActor()
    private var coreOutcome: CoreOutcome?

    private init(
        viewModel: AppViewModel,
        identityStore: AppUserIdentityStore,
        noteImportModel: NoteImportViewModel,
        featureFlags: AppFeatureFlags,
        bootstrapActor: AppBootstrapActor
    ) {
        self.viewModel = viewModel
        self.identityStore = identityStore
        self.noteImportModel = noteImportModel
        self.featureFlags = featureFlags
        self.bootstrapActor = bootstrapActor
        self.flowCoordinator = AppFlowCoordinator { _ in }
    }

    static func live() -> AppCompositionRoot {
        AppStartupPerformance.measure("StartupLightConstruction") {
            let placeholder = AppViewModel(
                entities: [],
                statements: [],
                observeLogEntries: [],
                startupMode: .deferred
            )
            let root = AppCompositionRoot(
                viewModel: placeholder,
                identityStore: AppUserIdentityStore(),
                noteImportModel: NoteImportViewModel(configurationError: "导入功能正在准备中…"),
                featureFlags: AppFeatureFlags.load(),
                bootstrapActor: AppBootstrapActor()
            )
            root.installStartupCoordinator()
            root.bindFlow(to: placeholder)
            AppStartupPerformance.event("AppCompositionLightConstructed")
            return root
        }
    }

    func performWhenInteractive(_ action: @escaping @MainActor (AppViewModel) -> Void) {
        startupCoordinator.performWhenInteractive { [weak self] in
            guard let self else { return }
            action(self.viewModel)
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
                let model: AppViewModel
                let interactiveSnapshot: AppInteractiveBootstrapSnapshot?
                switch coreOutcome {
                case .loaded(let snapshot):
                    interactiveSnapshot = await self.interactiveBootstrapActor.load(
                        paths: snapshot.paths,
                        repository: snapshot.repository,
                        governanceConfig: snapshot.governanceConfig
                    )
                    guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                    let graph = snapshot.graphSnapshot
                    model = AppViewModel(
                        entities: graph.entities,
                        statements: graph.statements,
                        episodes: graph.episodes,
                        observeLogEntries: graph.observeLogEntries,
                        repository: snapshot.repository,
                        databasePath: snapshot.paths.databaseURL.path,
                        storagePaths: snapshot.paths,
                        governanceConfig: snapshot.governanceConfig,
                        productOSRegistry: snapshot.productOSRegistry,
                        automationConfig: snapshot.automationConfig,
                        contactsProfileStore: snapshot.contactsProfileStore,
                        contactsRelationshipStore: snapshot.contactsRelationshipStore,
                        injectedMailStore: snapshot.mailStore,
                        injectedNativeSourceSearchBackend: snapshot.nativeSourceSearchBackend,
                        injectedSessionSearchIndexService: snapshot.sessionSearchIndexService,
                        injectedMemoryOSStore: snapshot.memoryOSStore,
                        injectedMemoryOSFacade: snapshot.memoryOSFacade,
                        injectedMemoryOSSearchHealthSummary: snapshot.memoryOSSearchHealthSummary,
                        injectedMemoryOSInitializationError: snapshot.memoryOSInitializationError,
                        startupMode: .deferred
                    )
                case .fallback(let error):
                    interactiveSnapshot = nil
                    model = AppViewModel.demo(startupMode: .deferred)
                    model.errorMessage = "已回退到演示数据：\(error)"
                }
                self.bindFlow(to: model)
                if let interactiveSnapshot {
                    model.prepareInteractiveStartup(snapshot: interactiveSnapshot)
                } else {
                    model.prepareDemoInteractiveStartup()
                }
                let noteImportModel = model.makeNoteImportViewModel()
                guard self.startupCoordinator.acceptsResults(for: generation) else {
                    model.shutdownRuntimeResources()
                    noteImportModel.stopJobMonitoring()
                    throw CancellationError()
                }
                self.viewModel.shutdownRuntimeResources()
                self.viewModel = model
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
                await self.viewModel.loadStartupContent(snapshot: snapshot)
            },
            startMaintenance: { [weak self] generation in
                guard let self, self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                self.viewModel.startTaskSchedulerTimer()
                await self.noteImportModel.recoverPersistedJobs()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.identityStore.restoreSession()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.viewModel.reconcileStartupRefreshTasks()
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                let snapshot: AppMaintenanceBootstrapSnapshot?
                switch self.coreOutcome {
                case .loaded(let core):
                    snapshot = await self.maintenanceBootstrapActor.load(paths: core.paths, repository: core.repository)
                case .fallback, .none:
                    snapshot = nil
                }
                guard self.startupCoordinator.acceptsResults(for: generation) else { throw CancellationError() }
                await self.viewModel.startStartupMaintenance(snapshot: snapshot)
            },
            shutdown: { [weak self] in
                guard let self else { return }
                self.noteImportModel.stopJobMonitoring()
                self.viewModel.shutdownRuntimeResources()
            }
        )
    }

    private func bindFlow(to model: AppViewModel) {
        flowCoordinator.replaceHandler { [weak self] intent in
            guard let self else { return }
            self.startupCoordinator.performWhenInteractive { [weak self] in
                guard let model = self?.viewModel else { return }
                switch intent {
                case let .navigate(selection): model.selection = selection
                case let .openSessionNotification(sessionID): model.openSessionFromNotification(sessionID)
                case .openCalendarSettings: model.selectSettingsSection(.calendar)
                case let .followRSSItem(request): model.handleRSSFollowRequest(request)
                }
            }
        }
        model.rssFeatureModel.onFollowRequest = { [weak flowCoordinator] request in
            flowCoordinator?.send(.followRSSItem(request))
        }
        model.calendarFeatureModel.onOpenSettingsRequest = { [weak flowCoordinator] in
            flowCoordinator?.send(.openCalendarSettings)
        }
    }
}
