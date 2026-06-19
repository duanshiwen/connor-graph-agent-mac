import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

enum SidebarItem: String, CaseIterable, Identifiable {
    case entities = "图谱节点"
    case search = "搜索"
    case observeLog = "观察日志"
    case agentChat = "智能体聊天"
    case promotionQueue = "提升队列"
    case graphWriteCandidates = "写入候选"
    case pendingApprovals = "权限审批"
    case memoryChangeLog = "记忆变更"
    case extractionDiagnostics = "记忆准入"
    case automation = "自动化"
    case productOS = "Product OS"
    case mail = "Mail"
    case calendar = "Calendar"
    case contacts = "Contacts"
    case rss = "RSS"
    case sources = "Sources"
    case skills = "Skills"
    case llmSettings = "模型设置"

    var id: String { rawValue }
}

struct WorkspaceRootDraft: Identifiable, Equatable {
    var id: String
    var displayName: String
    var path: String
    var role: String
    var isPrimary: Bool

    init(
        id: String = UUID().uuidString,
        displayName: String,
        path: String,
        role: String = "project",
        isPrimary: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.role = role
        self.isPrimary = isPrimary
    }
}

enum ConnorSettingsSection: String, CaseIterable, Identifiable {
    case app
    case ai
    case mail
    case calendar
    case contacts
    case rss
    case permissions
    case labels
    case statuses
    case shortcuts
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "应用"
        case .ai: "AI"
        case .mail: "邮件系统"
        case .calendar: "日历"
        case .contacts: "联系人"
        case .rss: "RSS 阅读"
        case .permissions: "权限"
        case .labels: "标签"
        case .statuses: "状态"
        case .shortcuts: "快捷键"
        case .preferences: "偏好"
        }
    }

    var subtitle: String {
        switch self {
        case .app: "通知和更新"
        case .ai: "模型、思考、连接"
        case .mail: "账户、同步、安全"
        case .calendar: "日程、账户能力、轻量管理"
        case .contacts: "联系人、搜索、轻量管理"
        case .rss: "订阅源、抓取、OPML"
        case .permissions: "默认权限和审批"
        case .labels: "管理会话标签"
        case .statuses: "管理会话状态"
        case .shortcuts: "键盘快捷键"
        case .preferences: "用户偏好"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app.badge"
        case .ai: "sparkles"
        case .mail: "envelope.badge"
        case .calendar: "calendar"
        case .contacts: "person.crop.circle.badge"
        case .rss: "dot.radiowaves.left.and.right"
        case .permissions: "shield"
        case .labels: "tag"
        case .statuses: "circle.dashed"
        case .shortcuts: "command"
        case .preferences: "person.crop.circle"
        }
    }
}

enum AppChatRuntimeUnavailableError: Error, LocalizedError {
    case nativeSessionManagerUnavailable

    var errorDescription: String? {
        switch self {
        case .nativeSessionManagerUnavailable:
            return "Native chat runtime is unavailable. Configure storage/runtime before sending messages."
        }
    }
}

enum ConnorAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "display"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
