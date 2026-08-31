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
                    runtime = AppRuntimeLifecycle.fallback(fallbackError: error)
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
                    self.installImFeature(
                        imStore: imStore,
                        applicationSupportDirectory: snapshot.paths.applicationSupportDirectory,
                        runtime: runtime
                    )
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
    private func installImFeature(
        imStore: SQLiteImStore,
        applicationSupportDirectory: URL,
        runtime: AppRuntimeLifecycle
    ) {
        let identityStore = self.identityStore
        let identityBox = ImSelfIdentityBox()
        if case .signedIn(let user) = identityStore.authenticationState {
            identityBox.value = ImSelfIdentity(id: Int64(user.id), displayName: user.displayName)
        }
        // 当前 IM 库对应的账号：启动时按已保存令牌解析，之后跟随登录态切换分库，
        // 避免把上一个账号的 IM 缓存混进当前账号（user id 隔离）。
        var currentStoreUserID: Int64? = ImStorageAccountResolver.storedUserID()
        weak var imFeatureRef: ImFeatureModel?
        imIdentityCancellable = identityStore.$authenticationState.sink { state in
            switch state {
            case .signedIn(let user):
                let nextUserID = Int64(user.id)
                identityBox.value = ImSelfIdentity(id: nextUserID, displayName: user.displayName)
                guard currentStoreUserID != nextUserID else { break }
                currentStoreUserID = nextUserID
                let targetURL = ImStorageAccountResolver.databaseURL(
                    applicationSupportDirectory: applicationSupportDirectory,
                    userID: nextUserID
                )
                try? ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(
                    applicationSupportDirectory: applicationSupportDirectory,
                    userID: nextUserID
                )
                do {
                    try imStore.switchAccount(databaseURL: targetURL)
                    Task { @MainActor in await imFeatureRef?.reloadAfterAccountSwitch() }
                } catch {
                    Task { @MainActor in imFeatureRef?.errorMessage = "切换 IM 账号存储失败：\(error.localizedDescription)" }
                }
            case .signedOut, .expired:
                // 登出/离线回退不切换 IM 库：保留当前账号缓存（与旧行为一致），
                // 换账号登录时上面的 signedIn 分支会切换到新账号分库。
                identityBox.value = nil
            case .restoring:
                break
            }
        }

        let imAttentionCoordinator = ImAttentionCoordinator()
        let center = ImMessageCenter(
            store: imStore,
            service: identityStore.makeImBackendService(),
            deviceID: identityStore.syncDeviceID,
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
            },
            makeForwardPager: { [weak runtime] in
                guard let runtime else { return nil }
                let sessionsLoader = runtime.graph.chat.sessions.makeForwardSessionPageLoader()
                return ForwardDestinationPager(
                    sessionsLoader: sessionsLoader ?? { _, _ in ([], nil) },
                    conversationsLoader: { cursor, limit in
                        let page = try await imStore.loadConversationPage(limit: limit, cursor: cursor)
                        return (
                            page.conversations.map { conversation in
                                ForwardDestination(
                                    key: "im:\(conversation.id)",
                                    targetID: conversation.id,
                                    title: conversation.title,
                                    subtitle: conversation.kind == .group ? "群聊" : "跟 \(conversation.participantName)",
                                    kind: conversation.kind == .group ? .group : .peer,
                                    updatedAt: TimeInterval(conversation.updatedAt) / 1_000
                                )
                            },
                            page.nextCursor
                        )
                    }
                )
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
        imFeatureRef = imFeature
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
            case let .openInteractiveWeb(request): command = .openInteractiveWeb(request)
            }
            self.sendWhenInteractive(command)
        }
        runtime.graph.rss.onFollowRequest = { [weak flowCoordinator] request in
            flowCoordinator?.send(.followRSSItem(request))
        }
        runtime.graph.interactiveWeb.onOpenInNewSession = { [weak flowCoordinator] url, title in
            flowCoordinator?.send(.openInteractiveWeb(InteractiveWebOpenRequest(url: url, title: title)))
        }
        runtime.graph.calendar.onOpenSettingsRequest = { [weak flowCoordinator] in
            flowCoordinator?.send(.openCalendarSettings)
        }
    }
}
