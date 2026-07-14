import Foundation
import ConnorGraphAppSupport

@MainActor
final class AppCompositionRoot: ObservableObject {
    let viewModel: AppViewModel
    let identityStore: AppUserIdentityStore
    let noteImportModel: NoteImportViewModel
    let featureFlags: AppFeatureFlags
    let flowCoordinator: AppFlowCoordinator
    let lifecycle: AppLifecycle

    init(
        viewModel: AppViewModel,
        identityStore: AppUserIdentityStore,
        noteImportModel: NoteImportViewModel,
        featureFlags: AppFeatureFlags,
        flowCoordinator: AppFlowCoordinator,
        lifecycle: AppLifecycle
    ) {
        self.viewModel = viewModel
        self.identityStore = identityStore
        self.noteImportModel = noteImportModel
        self.featureFlags = featureFlags
        self.flowCoordinator = flowCoordinator
        self.lifecycle = lifecycle
    }

    static func live() -> AppCompositionRoot {
        let viewModel = AppStartupPerformance.measure("AppViewModelLive") {
            AppViewModel.live()
        }
        let identityStore = AppUserIdentityStore()
        let noteImportModel = AppStartupPerformance.measure("NoteImportModelConstruction") {
            viewModel.makeNoteImportViewModel()
        }
        let featureFlags = AppFeatureFlags.load()
        let flowCoordinator = AppFlowCoordinator { intent in
            switch intent {
            case let .navigate(selection):
                viewModel.selection = selection
            case let .openSessionNotification(sessionID):
                viewModel.openSessionFromNotification(sessionID)
            case let .followRSSItem(request):
                viewModel.handleRSSFollowRequest(request)
            }
        }
        viewModel.rssFeatureModel.onFollowRequest = { request in
            flowCoordinator.send(.followRSSItem(request))
        }
        let lifecycle = AppLifecycle(
            startTaskScheduler: { [weak viewModel] in
                viewModel?.startTaskSchedulerTimer()
            },
            recoverNoteImports: { [weak noteImportModel] in
                await noteImportModel?.recoverPersistedJobs()
            },
            restoreIdentitySession: { [weak identityStore] in
                await identityStore?.restoreSession()
            },
            shutdownRuntimeResources: { [weak viewModel, weak noteImportModel] in
                noteImportModel?.stopJobMonitoring()
                viewModel?.shutdownRuntimeResources()
            }
        )
        let root = AppCompositionRoot(
            viewModel: viewModel,
            identityStore: identityStore,
            noteImportModel: noteImportModel,
            featureFlags: featureFlags,
            flowCoordinator: flowCoordinator,
            lifecycle: lifecycle
        )
        AppStartupPerformance.event("AppCompositionConstructed")
        return root
    }
}
