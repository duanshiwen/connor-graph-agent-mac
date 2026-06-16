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

    @Test func governanceConfigValidatesPlainLabels() throws {
        let config = AppSessionGovernanceConfig.default
        try config.validate()
        try config.validate(label: AgentSessionLabel(id: "important"))
        try config.validate(label: AgentSessionLabel(id: "priority"))
        try config.validate(label: AgentSessionLabel(id: "due"))
    }

    @Test func governanceDefaultsUseChineseDisplayNames() throws {
        let config = AppSessionGovernanceConfig.default
        #expect(AgentSessionStatus.allCases.map(\.displayName) == ["待办", "进行中", "等待中", "待审阅", "已完成", "受阻", "已归档"])
        #expect(config.statuses.map(\.name) == ["待办", "进行中", "等待中", "待审阅", "受阻", "已完成", "已归档"])
        #expect(config.labels.map(\.name) == ["重要", "研究", "优先级", "截止日期", "项目"])
    }

    @Test func governanceRepositoryNormalizesLegacyEnglishBuiltInDisplayNames() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = AppSessionGovernanceConfigRepository(configDirectory: root)
        let legacyConfig = AppSessionGovernanceConfig(
            statuses: [
                .init(id: AgentSessionStatus.todo.rawValue, name: "Todo", systemImage: "circle", sortOrder: 10),
                .init(id: AgentSessionStatus.inProgress.rawValue, name: "In Progress", systemImage: "play.circle", sortOrder: 20)
            ],
            labels: [
                .init(id: "important", name: "Important", colorName: "orange"),
                .init(id: "custom", name: "Custom", colorName: "blue")
            ]
        )
        try repository.save(legacyConfig)

        let loaded = try repository.loadOrCreateDefault()

        #expect(loaded.statuses.map(\.name) == ["待办", "进行中"])
        #expect(loaded.labels.map(\.name) == ["重要", "Custom"])
    }

    @Test func chatRepositoryPersistsStatusLabelsLegacyArchiveCompatibilityAndArtifacts() throws {
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

        let legacyArchived = try repository.markLegacyArchived(sessionID: session.id)
        #expect(legacyArchived.governance.isArchived)
        #expect(try repository.loadSessions(filter: .all).map(\.id) == [session.id])

        let restored = try repository.clearLegacyArchived(sessionID: session.id)
        #expect(!restored.governance.isArchived)
        #expect(restored.governance.status == .inProgress)
    }
}
