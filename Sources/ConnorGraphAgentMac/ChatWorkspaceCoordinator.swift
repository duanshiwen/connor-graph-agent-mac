import Foundation
import Observation
import ConnorGraphAppSupport

@MainActor
@Observable
final class ChatWorkspaceCoordinator {
    var stateSnapshotsBySessionID: [String: AppSessionStateSnapshot] = [:]
    var recordsBySessionID: [String: [AppSessionRecord]] = [:]
    private var workspaceModes = ChatSessionWorkspaceModeStore()

    func installState(_ state: AppSessionStateSnapshot?, sessionID: String) {
        if let state { stateSnapshotsBySessionID[sessionID] = state }
        else { stateSnapshotsBySessionID.removeValue(forKey: sessionID) }
    }

    func installRecords(_ records: [AppSessionRecord], sessionID: String) {
        recordsBySessionID[sessionID] = records
    }

    func state(for sessionID: String) -> AppSessionStateSnapshot? {
        stateSnapshotsBySessionID[sessionID]
    }

    func updateState(_ state: AppSessionStateSnapshot, sessionID: String) {
        stateSnapshotsBySessionID[sessionID] = state
    }

    func mode(for sessionID: String?) -> ChatSessionWorkspaceMode {
        workspaceModes.mode(for: sessionID)
    }

    func setMode(_ mode: ChatSessionWorkspaceMode, for sessionID: String?) {
        workspaceModes.setMode(mode, for: sessionID)
    }

    func removeSession(_ sessionID: String) {
        stateSnapshotsBySessionID.removeValue(forKey: sessionID)
        recordsBySessionID.removeValue(forKey: sessionID)
        workspaceModes = ChatSessionWorkspaceModeStore(
            modesBySessionID: workspaceModes.snapshot.filter { $0.key != sessionID }
        )
    }
}
