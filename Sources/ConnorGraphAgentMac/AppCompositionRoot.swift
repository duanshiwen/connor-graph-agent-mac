import Foundation
import Combine
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
    private var imIdentityCancellable: AnyCancellable?

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
            let backendBaseURL = URL(string: ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"] ?? "https://connor-agent.apecho.com/")!
            AppBackendConnectivity.shared.configure(baseURL: backendBaseURL)
            AppUpdateCenter.shared.checkOnLaunch()
            let placeholder = AppRuntimeLifecycle.placeholder()
            let root = AppCompositionRoot(
                runtime: placeholder,
                identityStore: AppUserIdentityStore(
                    baseURL: backendBaseURL,
                    transport: BackendConnectivityTrackingTransport(),
                    networkIsAvailable: { AppNetworkConnectivity.shared.isConnected },
                    serverIsReachable: { AppBackendConnectivity.shared.isReachable },
                    syncAvailability: Publishers.CombineLatest(
                        AppNetworkConnectivity.shared.$isConnected,
                        AppBackendConnectivity.shared.$state
                    )
                    .map { isConnected, backendState in isConnected && backendState != .unreachable }
                    .eraseToAnyPublisher()
                ),
                noteImportModel: NoteImportViewModel(configurationError: "导入功能正在准备中…"),
                featureFlags: AppFeatureFlags.load(),
                bootstrapActor: AppBootstrapActor()
            )
            root.installStartupCoordinator()
            root.bindCommandRouting(to: placeholder)
            root.identityStore.onDeviceSyncPass = { [weak root] in
                guard let root else { return }
                do {
                    try await root.runtime.syncAccountData(using: root.identityStore)
                } catch {
                    AppPerformanceLog.chatTurnLogger.warning("account.sync.failed error=\(String(describing: error), privacy: .public)")
                    throw error
                }
            }
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
                previousRuntime.graph.im?.shutdown()
                previousRuntime.shutdown()
                if case .loaded(let snapshot) = coreOutcome, let imStore = snapshot.imStore {
                    self.installImFeature(imStore: imStore, runtime: runtime)
                }
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

    /// Builds the IM stack: message center (REST + WS frames), identity snapshot
    /// box, forward-to-AI closures bridged onto the chat actions, then installs
    /// the feature model on the runtime's graph. Mirrors the Android container
    /// wiring for `ImMessageCenter`.
    private func installImFeature(imStore: SQLiteImStore, runtime: AppRuntimeLifecycle) {
        let identityStore = self.identityStore
        let identityBox = ImSelfIdentityBox()
        if case .signedIn(let user) = identityStore.authenticationState {
            identityBox.value = ImSelfIdentity(id: Int64(user.id), displayName: user.displayName)
        }
        imIdentityCancellable = identityStore.$authenticationState.sink { state in
            switch state {
            case .signedIn(let user):
                identityBox.value = ImSelfIdentity(id: Int64(user.id), displayName: user.displayName)
            case .signedOut, .expired:
                identityBox.value = nil
            case .restoring:
                break
            }
        }

        let imAttentionCoordinator = ImAttentionCoordinator()
        let center = ImMessageCenter(
            store: imStore,
            service: identityStore.makeImBackendService(),
            sendFrame: { [weak identityStore] text in
                guard let identityStore else { return false }
                return await identityStore.sendImFrame(text)
            },
            currentIdentity: { identityBox.value },
            onRealtimeEvent: { event in
                await imAttentionCoordinator.handle(event)
            }
        )
        identityStore.onImFrame = { type, rawText in
            await center.handleFrame(type: type, text: rawText)
        }
        identityStore.onImSocketStateChange = { connected in
            if connected { await center.handleSocketConnected() }
        }

        let friendProvisioner = ImFriendPersonProvisioner(
            profileStore: runtime.graph.contacts.agentProfileStore,
            imStore: imStore
        )
        let chatActions = runtime.graph.chatActions
        let imFeature = ImFeatureModel(
            store: imStore,
            center: center,
            identityStore: identityStore,
            friendProvisioner: friendProvisioner,
            forwardFacade: { [weak runtime] in runtime?.imForwardMemoryFacade },
            forwardToNewSession: { prompt in
                await chatActions.run.submitNewChat(prompt: prompt, displayPrompt: nil)
            },
            forwardToExistingSession: { sessionID, prompt in
                chatActions.session.selectChatSession(sessionID)
                return await chatActions.run.submitChat(prompt: prompt, clearComposer: false)
            },
            generateTitle: { [weak runtime] messages, conversationID in
                guard let runtime else { throw CancellationError() }
                return try await runtime.generateImConversationTitle(messages: messages, conversationID: conversationID)
            }
        )
        imAttentionCoordinator.notificationSettings = { [weak runtime] in
            guard let runtime else { return (false, .none) }
            return (
                runtime.appSettingsModel.desktopNotificationsEnabled,
                runtime.appSettingsModel.sessionNewMessageNotificationLevel
            )
        }
        imAttentionCoordinator.isConversationVisible = { [weak runtime, weak imFeature] conversationID in
            runtime?.selection == .agentChat && imFeature?.selectedConversationId == conversationID
        }
        imAttentionCoordinator.isContactsVisible = { [weak runtime] in
            runtime?.selection == .contacts
        }
        imAttentionCoordinator.canUseUserNotifications = {
            Bundle.main.bundleURL.pathExtension == "app"
        }
        runtime.graph.im = imFeature
        imFeature.start()
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
