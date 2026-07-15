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

    @discardableResult
    func select(_ item: SidebarItem) -> Bool {
        let previous = selection
        guard previous != item else {
            AppPerformanceLog.sidebarNavigationLogger.debug(
                "sidebar.route.commit from=\(previous?.rawValue ?? "none", privacy: .public) to=\(item.rawValue, privacy: .public) changed=false duration=0ms"
            )
            return false
        }
        let measured = AppPerformanceLog.measure { selection = item }
        AppPerformanceLog.sidebarNavigationLogger.info(
            "sidebar.route.commit from=\(previous?.rawValue ?? "none", privacy: .public) to=\(item.rawValue, privacy: .public) changed=true duration=\(measured.milliseconds, privacy: .public)ms"
        )
        return true
    }

    func selectSettingsSection(_ section: ConnorSettingsSection) {
        selectedSettingsSection = section
        select(.llmSettings)
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
            select(.agentChat)
        case .browserWorkspace:
            break
        case .search:
            select(.search)
        case .graphEntities:
            select(.entities)
        case .approvals:
            select(.pendingApprovals)
        case .automation, .localAutomationSurface:
            select(.scheduledTasks)
        case .productOS:
            select(.productOS)
        case .calendar:
            select(.calendar)
        case .contacts:
            select(.contacts)
        case .mail:
            select(.mail)
        case .rss:
            select(.rss)
        case .sources:
            select(.sources)
        case .skills:
            select(.skills)
        case .settings:
            select(.llmSettings)
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
