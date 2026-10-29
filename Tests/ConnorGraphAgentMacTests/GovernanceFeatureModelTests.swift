import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Test func governanceModelCreatesUniqueLabelSlugs() {
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(labels: [
        .init(id: "project", name: "Project", colorName: "blue")
    ]))
    model.upsertLabel(.init(id: "", name: "Project", colorName: "green"))
    #expect(model.config.labels.map(\.id) == ["project", "project_2"])
    #expect(!ConnorSettingsSection.allCases.map(\.rawValue).contains("statuses"))
}

@MainActor
@Test func governanceModelRemovesLabelFromSessionsBeforeSavingDefinition() {
    let label = AgentSessionLabelDefinition(id: "important", name: "重要", colorName: "red", systemImage: "flag")
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(labels: [label]))
    var calls: [String] = []
    var message: String?
    var deleted: GovernanceDefinitionDeletion?
    model.removeLabelFromSessions = { id in calls.append("remove:\(id)"); return 2 }
    model.onConfigSaved = { config in calls.append("save:\(config.labels.count)") }
    model.onSettingsMessage = { value, section in
        calls.append("message:\(section.id)")
        message = value
    }
    model.onDefinitionDeleted = { deleted = $0 }

    model.deleteLabel(label)

    #expect(calls == ["remove:important", "save:0", "message:labels"])
    #expect(message == "标签“重要”已删除，并已从 2 个会话移除。")
    #expect(deleted == .label("important"))
    #expect(model.config.labels.isEmpty)
}

@MainActor
@Test func governanceModelKeepsSavedLabelWhenDownstreamReloadFails() {
    struct ReloadFailure: Error {}
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(labels: []))
    model.onConfigSaved = { _ in throw ReloadFailure() }
    model.upsertLabel(.init(id: "", name: "Project", colorName: "green"))
    #expect(model.config.labels.first?.name == "Project")
    #expect(model.errorMessage != nil)
}
