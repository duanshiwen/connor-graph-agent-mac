import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Product OS Phase 1 Tests")
struct ProductOSPhase1Tests {
    @Test func storagePathsExposeSingleHomeProductOSDirectories() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: base)

        #expect(paths.applicationSupportDirectory.lastPathComponent == "Connor")
        #expect(paths.automationsDirectory.path.contains("/Connor/automations"))
        #expect(paths.labelsDirectory.path.contains("/Connor/labels"))
        #expect(paths.statusesDirectory.path.contains("/Connor/statuses"))
        #expect(paths.artifactsDirectory.path.contains("/Connor/artifacts"))
        #expect(!paths.applicationSupportDirectory.path.contains("workspace"))

        let artifactDirs = paths.sessionArtifactDirectories(sessionID: "session-1")
        #expect(artifactDirs.plans.path.contains("/Connor/sessions/session-1/plans"))
        #expect(artifactDirs.data.path.contains("/Connor/sessions/session-1/data"))
        #expect(artifactDirs.attachments.path.contains("/Connor/sessions/session-1/attachments"))
    }

    @Test func governanceConfigValidatesTypedLabels() throws {
        let config = AppSessionGovernanceConfig.default
        try config.validate()
        try config.validate(label: AgentSessionLabel(id: "important"))
        try config.validate(label: AgentSessionLabel(id: "priority", value: "3"))
        try config.validate(label: AgentSessionLabel(id: "due", value: "2026-06-11"))

        #expect(throws: AppSessionGovernanceConfigError.self) {
            try config.validate(label: AgentSessionLabel(id: "important", value: "yes"))
        }
        #expect(throws: AppSessionGovernanceConfigError.self) {
            try config.validate(label: AgentSessionLabel(id: "priority", value: "high"))
        }
    }

    @Test func chatRepositoryPersistsStatusLabelsArchiveAndArtifacts() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store, storagePaths: paths)

        let session = try repository.createSession(title: "Phase 1")
        let labeled = try repository.setLabels(sessionID: session.id, labels: [AgentSessionLabel(id: "important")])
        #expect(labeled.governance.labels.map(\.id) == ["important"])

        let inProgress = try repository.setStatus(sessionID: session.id, status: .inProgress)
        #expect(inProgress.governance.status == .inProgress)

        let dirs = try repository.artifactDirectories(sessionID: session.id)
        #expect(dirs != nil)
        #expect(FileManager.default.fileExists(atPath: dirs!.plans.path))

        let archived = try repository.archive(sessionID: session.id)
        #expect(archived.governance.isArchived)
        #expect(try repository.loadSessions(filter: .inbox).isEmpty)
        #expect(try repository.loadSessions(filter: .archived).map(\.id) == [session.id])

        let restored = try repository.restore(sessionID: session.id)
        #expect(!restored.governance.isArchived)
        #expect(restored.governance.status == .todo)
    }
}
