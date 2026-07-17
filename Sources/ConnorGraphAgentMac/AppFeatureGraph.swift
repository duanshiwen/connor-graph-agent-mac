import AppKit
import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class AppErrorFeatureModel {
    var message: String?

    init(message: String? = nil) {
        self.message = message
    }
}

@MainActor
final class AppShellRuntimeActions {
    let openURL: (URL) -> Void
    let activateSettingsSideEffects: () -> Void

    init(openURL: @escaping (URL) -> Void, activateSettingsSideEffects: @escaping () -> Void) {
        self.openURL = openURL
        self.activateSettingsSideEffects = activateSettingsSideEffects
    }
}

@MainActor
final class SettingsRuntimeActions {
    let load: () -> Void
    let openProjectHelp: () -> Void
    let openURL: (URL) -> Void

    init(load: @escaping () -> Void, openProjectHelp: @escaping () -> Void, openURL: @escaping (URL) -> Void) {
        self.load = load
        self.openProjectHelp = openProjectHelp
        self.openURL = openURL
    }
}

@MainActor
final class ChatSessionListActions {
    let isSubmitting: (String) -> Bool
    let canDelete: (String) -> Bool
    let rename: (String, String) -> Void
    let setStatus: (String, AgentSessionStatus) -> Void
    let toggleLabel: (String, String) -> Void
    let regenerateTitle: (String) -> Void
    let delete: (String) -> Void

    init(
        isSubmitting: @escaping (String) -> Bool,
        canDelete: @escaping (String) -> Bool,
        rename: @escaping (String, String) -> Void,
        setStatus: @escaping (String, AgentSessionStatus) -> Void,
        toggleLabel: @escaping (String, String) -> Void,
        regenerateTitle: @escaping (String) -> Void,
        delete: @escaping (String) -> Void
    ) {
        self.isSubmitting = isSubmitting
        self.canDelete = canDelete
        self.rename = rename
        self.setStatus = setStatus
        self.toggleLabel = toggleLabel
        self.regenerateTitle = regenerateTitle
        self.delete = delete
    }
}

@MainActor
final class AppFeatureGraph {
    let shell: AppShellFeatureModel
    let errors: AppErrorFeatureModel
    let aiConnections: AIConnectionsFeatureModel
    let governance: GovernanceFeatureModel
    let chat: ChatFeatureModel
    let chatActions: ChatFeatureActions
    let chatSessionListActions: ChatSessionListActions
    let graphDiagnostics: GraphDiagnosticsModel
    let productOS: ProductOSControlFeatureModel
    let tasks: TaskAutomationFeatureModel
    let sources: SourceRuntimeFeatureModel
    let calendar: CalendarFeatureModel
    let contacts: ContactsFeatureModel
    let mail: MailFeatureModel
    let browser: BrowserFeatureModel
    let globalSearch: GlobalSearchFeatureModel
    let knowledgeMarketplace: CloudKnowledgeMarketplaceStore
    let knowledgeCreator: CloudKnowledgeCreatorStore
    let rss: RSSFeatureModel
    let skills: SkillRuntimeFeatureModel
    let appSettings: AppSettingsFeatureModel
    let inputSettings: InputSettingsFeatureModel
    let userPreferences: UserPreferencesFeatureModel
    let workspaceSettings: WorkspaceSettingsFeatureModel
    let permissionSettings: PermissionSettingsFeatureModel
    let shellActions: AppShellRuntimeActions
    let settingsActions: SettingsRuntimeActions
    let commercialReadinessDashboard: () -> CommercialReadinessDashboard

    init(
        shell: AppShellFeatureModel,
        errors: AppErrorFeatureModel,
        aiConnections: AIConnectionsFeatureModel,
        governance: GovernanceFeatureModel,
        chat: ChatFeatureModel,
        chatActions: ChatFeatureActions,
        chatSessionListActions: ChatSessionListActions,
        graphDiagnostics: GraphDiagnosticsModel,
        productOS: ProductOSControlFeatureModel,
        tasks: TaskAutomationFeatureModel,
        sources: SourceRuntimeFeatureModel,
        calendar: CalendarFeatureModel,
        contacts: ContactsFeatureModel,
        mail: MailFeatureModel,
        browser: BrowserFeatureModel,
        globalSearch: GlobalSearchFeatureModel,
        knowledgeMarketplace: CloudKnowledgeMarketplaceStore,
        knowledgeCreator: CloudKnowledgeCreatorStore,
        rss: RSSFeatureModel,
        skills: SkillRuntimeFeatureModel,
        appSettings: AppSettingsFeatureModel,
        inputSettings: InputSettingsFeatureModel,
        userPreferences: UserPreferencesFeatureModel,
        workspaceSettings: WorkspaceSettingsFeatureModel,
        permissionSettings: PermissionSettingsFeatureModel,
        shellActions: AppShellRuntimeActions,
        settingsActions: SettingsRuntimeActions,
        commercialReadinessDashboard: @escaping () -> CommercialReadinessDashboard
    ) {
        self.shell = shell
        self.errors = errors
        self.aiConnections = aiConnections
        self.governance = governance
        self.chat = chat
        self.chatActions = chatActions
        self.chatSessionListActions = chatSessionListActions
        self.graphDiagnostics = graphDiagnostics
        self.productOS = productOS
        self.tasks = tasks
        self.sources = sources
        self.calendar = calendar
        self.contacts = contacts
        self.mail = mail
        self.browser = browser
        self.globalSearch = globalSearch
        self.knowledgeMarketplace = knowledgeMarketplace
        self.knowledgeCreator = knowledgeCreator
        self.rss = rss
        self.skills = skills
        self.appSettings = appSettings
        self.inputSettings = inputSettings
        self.userPreferences = userPreferences
        self.workspaceSettings = workspaceSettings
        self.permissionSettings = permissionSettings
        self.shellActions = shellActions
        self.settingsActions = settingsActions
        self.commercialReadinessDashboard = commercialReadinessDashboard
    }
}
