import Foundation
import Observation
import ConnorGraphAppSupport

@MainActor
@Observable
final class AppShellFeatureModel {
    var selection: SidebarItem? = .agentChat
    var selectedSettingsSection: ConnorSettingsSection = .app
    private(set) var focusTopSearchRequestID: UUID?
    private(set) var settingsSectionMessageStore = SettingsSectionMessageStore()

    func select(_ item: SidebarItem) {
        selection = item
    }

    func selectSettingsSection(_ section: ConnorSettingsSection) {
        selectedSettingsSection = section
        selection = .llmSettings
    }

    func requestTopSearchFocus() {
        focusTopSearchRequestID = UUID()
    }

    func settingsMessage(for section: ConnorSettingsSection) -> String? {
        settingsSectionMessageStore.message(for: section)
    }

    func setSettingsMessage(_ message: String?, for section: ConnorSettingsSection) {
        settingsSectionMessageStore.set(message, for: section)
    }

    func clearSettingsMessage(for section: ConnorSettingsSection) {
        settingsSectionMessageStore.clear(for: section)
    }

    func clearAllSettingsMessages() {
        settingsSectionMessageStore = SettingsSectionMessageStore()
    }

    func applyNavigation(_ item: ConnorNativeShellItem) {
        switch item {
        case .home, .agentChat, .graphMemory:
            selection = .agentChat
        case .browserWorkspace:
            break
        case .search:
            selection = .search
        case .graphEntities:
            selection = .entities
        case .approvals:
            selection = .pendingApprovals
        case .automation, .localAutomationSurface:
            selection = .scheduledTasks
        case .productOS:
            selection = .productOS
        case .calendar:
            selection = .calendar
        case .contacts:
            selection = .contacts
        case .mail:
            selection = .mail
        case .rss:
            selection = .rss
        case .sources:
            selection = .sources
        case .skills:
            selection = .skills
        case .settings:
            selection = .llmSettings
        }
    }
}

enum AppCommand: Sendable, Equatable {
    case shortcut(AgentRuntimeShortcutAction)
    case newNote
    case selectSidebar(SidebarItem)
    case navigate(ConnorNativeShellItem)
    case openSessionNotification(String)
    case openCalendarSettings
    case followRSSItem(RSSFollowRequest)
}

@MainActor
final class AppCommandRouter {
    typealias Handler = @MainActor (AppCommand) -> Void

    private var handler: Handler

    init(handler: @escaping Handler = { _ in }) {
        self.handler = handler
    }

    func send(_ command: AppCommand) {
        handler(command)
    }

    func replaceHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }
}
