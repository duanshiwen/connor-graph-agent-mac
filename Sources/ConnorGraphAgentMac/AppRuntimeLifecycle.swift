import Foundation
import ConnorGraphAppSupport

@MainActor
final class AppRuntimeLifecycle {
    private let model: AppRuntimeOrchestrator
    let graph: AppFeatureGraph

    private init(model: AppRuntimeOrchestrator) {
        self.model = model
        self.graph = Self.makeFeatureGraph(model: model)
    }

    static func placeholder() -> AppRuntimeLifecycle {
        AppRuntimeLifecycle(model: AppRuntimeOrchestrator(
            entities: [],
            statements: [],
            observeLogEntries: [],
            startupMode: .deferred
        ))
    }

    static func live(core snapshot: CoreBootstrapSnapshot) -> AppRuntimeLifecycle {
        let graph = snapshot.graphSnapshot
        return AppRuntimeLifecycle(model: AppRuntimeOrchestrator(
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
        ))
    }

    static func demo(fallbackError: Error) -> AppRuntimeLifecycle {
        let demo = AppDemoGraphSnapshotFactory.make()
        let model = AppRuntimeOrchestrator(
            entities: demo.entities,
            statements: demo.statements,
            episodes: demo.episodes,
            observeLogEntries: demo.observeLogEntries,
            startupMode: .deferred
        )
        model.errorMessage = "已回退到演示数据：\(fallbackError)"
        return AppRuntimeLifecycle(model: model)
    }

    func prepareInteractive(snapshot: AppInteractiveBootstrapSnapshot?) {
        if let snapshot {
            model.prepareInteractiveStartup(snapshot: snapshot)
        } else {
            model.prepareDemoInteractiveStartup()
        }
    }

    func makeNoteImportModel() -> NoteImportViewModel {
        model.noteImportRuntimeFactory.makeModel()
    }

    func loadContent(snapshot: AppContentBootstrapSnapshot?) async {
        await model.loadStartupContent(snapshot: snapshot)
    }

    func startScheduler() {
        model.maintenanceCoordinator.startScheduler()
    }

    func reconcileStartupRefreshTasks() async {
        await model.reconcileStartupRefreshTasks()
    }

    func startMaintenance(snapshot: AppMaintenanceBootstrapSnapshot?) async {
        await model.startStartupMaintenance(snapshot: snapshot)
    }

    func perform(_ command: AppCommand) {
        switch command {
        case let .shortcut(action):
            model.performShortcutAction(action)
        case .newNote:
            model.newNoteSession()
        case let .selectSidebar(selection):
            model.shellFeatureModel.select(selection)
        case let .navigate(item):
            model.navigate(to: item)
        case let .openSessionNotification(sessionID):
            model.openSessionFromNotification(sessionID)
        case .openCalendarSettings:
            model.selectSettingsSection(.calendar)
        case let .followRSSItem(request):
            model.handleRSSFollowRequest(request)
        }
    }

    func shutdown() {
        model.shutdownRuntimeResources()
    }

    private static func makeFeatureGraph(model: AppRuntimeOrchestrator) -> AppFeatureGraph {
        let session = ClosureChatSessionPort(
            isLoading: { [weak model] in model?.isLoadingSelectedChatSessionDetail ?? false },
            reloadIfNeeded: { [weak model] restore in model?.reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode: restore) },
            reload: { [weak model] restore in model?.reloadChatSessions(restoreWorkspaceMode: restore) },
            new: { [weak model] in model?.newChatSession() },
            select: { [weak model] in model?.selectChatSession($0) },
            rename: { [weak model] in model?.renameChatSession($0, title: $1) },
            filter: { [weak model] in model?.setSessionListFilter($0, restoreWorkspaceMode: $1) },
            status: { [weak model] in model?.setSelectedSessionStatus($0) },
            flag: { [weak model] in model?.toggleSelectedSessionFlag() },
            label: { [weak model] in model?.toggleSelectedSessionLabel($0) }
        )
        let run = ClosureChatRunPort(
            backgroundTasks: { [weak model] in
                guard let model else { return [] }
                return model.chatBackgroundTaskCoordinator.tasks(for: model.chatFeatureModel.sessions.selectedSessionID)
            },
            hasBackgroundTask: { [weak model] in
                guard let model, let sessionID = model.chatFeatureModel.sessions.selectedSessionID else { return false }
                return model.chatBackgroundTaskCoordinator.hasRunningTask(sessionID: sessionID)
            },
            summaryFreshness: { [weak model] in model?.latestChatSummaryFreshness },
            summaryContext: { [weak model] in model?.latestChatSummaryContextMessage ?? "" },
            submit: { [weak model] prompt, clear, display, attachments, people in
                await model?.submitChat(prompt: prompt, clearComposer: clear, displayPrompt: display, attachments: attachments, personReferences: people)
            },
            cancel: { [weak model] in model?.cancelActiveChatRun() },
            permission: { [weak model] in model?.setAgentPermissionMode($0) },
            timeline: { [weak model] in model?.restoredAgentEventTimeline(for: $0) ?? [] },
            markdown: { [weak model] in model?.markdownPersistentCacheContext(messageID: $0) },
            copy: { [weak model] in model?.copyAssistantMessageToPasteboard($0) },
            export: { [weak model] in model?.exportAssistantMessageToFile($0, now: $1) },
            download: { [weak model] in model?.downloadPreviewImage($0) },
            clearOverride: { [weak model] in model?.clearSessionLLMOverride() },
            selectModel: { [weak model] in model?.selectLLMModel($0, providerMode: $1, connectionID: $2) },
            thinking: { [weak model] in model?.selectLLMThinkingLevel($0) },
            defaultThinking: { [weak model] in model?.selectDefaultLLMThinkingLevel($0) },
            reloadModels: { [weak model] in await model?.reloadLLMModelConnections() }
        )
        let chatActions = ChatFeatureActions(
            session: session,
            composer: model.chatComposerCoordinator,
            run: run,
            approval: model.chatApprovalCoordinator,
            workspace: ClosureChatWorkspacePort(
                open: { [weak model] in model?.openURLInCurrentChatBrowser($0) },
                record: { [weak model] in model?.appendSessionRecord(kind: $0, title: $1, body: $2, metadata: $3, sessionID: $4) }
            ),
            errors: ClosureChatErrorPort(
                get: { [weak model] in model?.errorMessage },
                set: { [weak model] in model?.errorMessage = $0 }
            ),
            dependencies: ChatFeatureDependencies(
                browser: model.browserFeatureModel,
                appSettings: model.appSettingsModel,
                inputSettings: model.inputSettingsModel,
                workspaceSettings: model.workspaceSettingsModel,
                skills: model.skillRuntimeModel,
                contacts: model.contactsFeatureModel,
                governance: model.governanceModel,
                aiConnections: model.aiConnectionsModel,
                permissionMode: { [weak model] in model?.agentPermissionMode ?? .askToWrite },
                sessionHasLLMOverride: { [weak model] in model?.sessionHasLLMOverride ?? false }
            )
        )
        return AppFeatureGraph(
            shell: model.shellFeatureModel,
            errors: model.errorFeatureModel,
            aiConnections: model.aiConnectionsModel,
            governance: model.governanceModel,
            chat: model.chatFeatureModel,
            chatActions: chatActions,
            chatSessionListActions: ChatSessionListActions(
                isSubmitting: { [weak model] in model?.isChatSessionSubmitting($0) ?? false },
                canDelete: { [weak model] in model?.canDeleteChatSession($0) ?? true },
                rename: { [weak model] in model?.renameChatSession($0, title: $1) },
                setStatus: { [weak model] in model?.setChatSessionStatus($0, status: $1) },
                toggleLabel: { [weak model] in model?.toggleChatSessionLabel($0, labelID: $1) },
                regenerateTitle: { [weak model] in model?.regenerateChatSessionTitle($0) },
                delete: { [weak model] in model?.deleteChatSession($0) }
            ),
            graphDiagnostics: model.graphDiagnosticsModel,
            productOS: model.productOSControlModel,
            tasks: model.taskAutomationModel,
            sources: model.sourceRuntimeModel,
            calendar: model.calendarFeatureModel,
            contacts: model.contactsFeatureModel,
            mail: model.mailFeatureModel,
            browser: model.browserFeatureModel,
            globalSearch: model.globalSearchFeatureModel,
            rss: model.rssFeatureModel,
            skills: model.skillRuntimeModel,
            appSettings: model.appSettingsModel,
            inputSettings: model.inputSettingsModel,
            userPreferences: model.userPreferencesModel,
            workspaceSettings: model.workspaceSettingsModel,
            permissionSettings: model.permissionSettingsModel,
            shellActions: AppShellRuntimeActions(
                openURL: { [weak model] in model?.openURLInSystemDefaultBrowser($0) },
                activateSettingsSideEffects: { [weak model] in model?.activateRuntimeSettingsSideEffectsAfterLaunch() }
            ),
            settingsActions: SettingsRuntimeActions(
                load: { [weak model] in model?.loadRuntimeSettings() },
                openProjectHelp: { [weak model] in model?.openProjectGitHubHelp() },
                openURL: { [weak model] in model?.openURLInSystemDefaultBrowser($0) }
            ),
            commercialReadinessDashboard: { [weak model] in model?.commercialReadinessDashboard ?? CommercialReadinessDashboard(cards: []) }
        )
    }
}
