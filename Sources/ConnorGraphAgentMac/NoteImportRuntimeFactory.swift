import Foundation
import ConnorGraphAppSupport
import ConnorGraphCore

struct NoteImportRuntimeFactory {
    let databasePath: String?
    let sessionRepository: AppChatSessionRepository?
    let runCoordinator: ChatRunCoordinator
    let storagePaths: AppStoragePaths?
    let onSessionImported: @MainActor (AgentSession) -> Void

    @MainActor
    func makeModel() -> NoteImportViewModel {
        guard let databasePath, let sessionRepository, let runtimeFactory = runCoordinator.runtimeFactory, let storagePaths else {
            return NoteImportViewModel(configurationError: "导入运行时不可用，请重新启动应用。")
        }
        do {
            let ledger = try AppNoteImportRepository(databasePath: databasePath)
            let attachmentStore = AppSessionAttachmentStore(paths: storagePaths)
            let sessionService = HeadlessNoteSessionService(
                repository: sessionRepository,
                managerFactory: { session in runtimeFactory.makeNativeSessionManager(session: session, permissionMode: .readOnly) },
                attachmentStore: attachmentStore
            )
            let coordinator = NoteImportCoordinator(
                ledger: ledger,
                sessionService: sessionService,
                attachmentImporter: NoteImportAttachmentImporter(store: attachmentStore),
                payloadStore: NoteImportPayloadStore(rootDirectory: storagePaths.artifactsDirectory.appendingPathComponent("note-import-staging", isDirectory: true)),
                onSessionImported: { session in
                    Task { @MainActor in
                        onSessionImported(session)
                    }
                }
            )
            return NoteImportViewModel(
                ledger: ledger,
                coordinator: coordinator,
                executionSupervisor: NoteImportExecutionSupervisor(coordinator: coordinator),
                sourceAccessService: NoteImportSourceAccessService()
            )
        } catch {
            return NoteImportViewModel(configurationError: "无法初始化导入功能：\(error.localizedDescription)")
        }
    }
}
