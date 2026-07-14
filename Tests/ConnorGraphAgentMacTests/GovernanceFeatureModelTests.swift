import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Test func governanceModelCreatesStableUniqueSlugsAndEmitsSectionMessage() {
    let existing = AgentSessionStatusDefinition(id: "in_review", name: "Existing", systemImage: "circle", sortOrder: 10, isTerminal: false)
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(statuses: [existing], labels: []))
    var messages: [(String, ConnorSettingsSection)] = []
    model.onSettingsMessage = { messages.append(($0, $1)) }

    model.upsertStatus(AgentSessionStatusDefinition(id: "", name: "In Review", systemImage: "clock", sortOrder: 20, isTerminal: false))

    #expect(model.config.statuses.map(\.id).contains("in_review_2"))
    #expect(messages.count == 1)
    #expect(messages[0].0 == "状态定义已保存。")
    #expect(messages[0].1 == .statuses)
}

@MainActor
@Test func governanceModelBlocksDeletingInUseStatusWithExistingMessage() {
    let status = AgentSessionStatusDefinition(id: AgentSessionStatus.inProgress.rawValue, name: "进行中", systemImage: "clock", sortOrder: 20, isTerminal: false)
    let fallback = AgentSessionStatusDefinition(id: AgentSessionStatus.todo.rawValue, name: "待办", systemImage: "circle", sortOrder: 10, isTerminal: false)
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(statuses: [fallback, status], labels: []))
    var session = AgentSession(id: "session-1")
    session.governance.status = .inProgress
    model.sessionsProvider = { [session] }

    #expect(!model.canDeleteStatus(status))
    model.deleteStatus(status)

    #expect(model.config.statuses.contains(where: { $0.id == status.id }))
    #expect(model.errorMessage == "无法删除状态“进行中”: 仍有 1 个会话处于此状态。")
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
@Test func governanceModelKeepsSavedConfigWhenDownstreamAutomationReloadFails() {
    struct ReloadFailure: Error {}
    let original = AgentSessionStatusDefinition(id: "todo", name: "待办", systemImage: "circle", sortOrder: 10, isTerminal: false)
    let model = GovernanceFeatureModel(config: AppSessionGovernanceConfig(statuses: [original], labels: []))
    model.onConfigSaved = { _ in throw ReloadFailure() }

    model.upsertStatus(AgentSessionStatusDefinition(id: "todo", name: "新的待办", systemImage: "clock", sortOrder: 10, isTerminal: false))

    #expect(model.config.statuses.first?.name == "新的待办")
    #expect(model.errorMessage != nil)
}
