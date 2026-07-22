import Foundation

public enum AgentToolActivityPhase: String, Codable, Sendable, Equatable {
    case requested
    case approved
    case running
    case finished
    case failed
}

public enum AgentToolSemanticKind: String, Codable, Sendable, Equatable {
    case readFile
    case writeFile
    case editFile
    case listDirectory
    case findFiles
    case searchFiles
    case shellCommand
    case swiftBuild
    case swiftTest
    case swiftRun
    case xcodeBuild
    case git
    case packageManager
    case python
    case node
    case browser
    case calendar
    case mcp
    case unknown
}

public enum AgentToolDisplayNameResolver {
    private static let catalog: [String: String] = [
        "read": "读取文件", "ls": "查看目录", "glob": "查找文件", "grep": "搜索文件内容",
        "bash": "执行终端命令", "write": "写入文件", "edit": "编辑文件", "multiedit": "批量编辑文件",
        "get_current_time": "获取当前时间", "time_analyze_ranges": "分析时间范围",
        "graph_search": "搜索知识图谱", "browser_fetch": "读取浏览器页面", "web_search": "搜索网页", "web_fetch": "读取网页内容",
        "browser_history_search": "搜索浏览历史", "browser_history_get": "读取浏览记录",
        "generate_image": "生成图片", "edit_image": "编辑图片",
        "connor_skill_activate": "启用技能", "connor_skill_list": "查看可用技能", "skill_list": "查看可用技能",
        "connor_skill_create": "创建技能", "connor_skill_update": "更新技能", "connor_skill_delete": "删除技能",
        "session_get_status": "查看会话状态", "session_set_status": "更新会话状态", "session_list_statuses": "查看可用会话状态",
        "personality_get_current": "查看康纳同学性格", "personality_propose_update": "生成人格变更提议", "personality_commit_proposal": "应用人格变更",
        "tasks_list": "查看任务", "tasks_create_scheduled_session_message": "创建定时会话任务", "tasks_create_session_status_message": "创建状态触发任务",
        "contact_search": "搜索联系人", "contact_create_draft": "创建联系人草稿", "contact_commit_draft": "保存联系人",
        "contacts_read": "读取联系人", "contacts_write": "更新联系人",
        "calendar_search_events": "搜索日程", "calendar_read": "读取日历", "calendar_write": "更新日历",
        "mail_list_accounts": "查看邮箱账户", "mail_search_messages": "搜索邮件", "mail_list_recent_messages": "查看近期邮件",
        "mail_search_messages_with_body_preview": "搜索邮件正文", "mail_list_recent_messages_with_body_preview": "查看近期邮件正文",
        "mail_get_message": "读取邮件", "mail_set_read_state": "更新邮件阅读状态", "mail_create_draft": "创建邮件草稿", "mail_send_draft": "发送邮件",
        "rss_list_sources": "查看 RSS 订阅源", "rss_add_source": "添加 RSS 订阅源", "rss_sync_source": "同步 RSS 订阅源",
        "rss_list_items": "查看 RSS 文章", "rss_search_items": "搜索 RSS 文章", "rss_get_item": "读取 RSS 文章",
        "rss_set_read_state": "更新 RSS 阅读状态", "rss_set_star_state": "更新 RSS 收藏状态", "rss_set_hidden_state": "更新 RSS 隐藏状态",
        "rss_import_opml": "导入 RSS 订阅", "rss_export_opml": "导出 RSS 订阅", "rss_create_evidence_candidate": "保存 RSS 证据",
        "memory_os_recent_context": "查询近期记忆", "memory_os_knowledge_context": "查询长期记忆", "memory_os_search": "搜索记忆", "conversation_history_search": "查询聊天记录",
        "memory_os_get_current_user_profile": "读取用户偏好", "memory_os_update_current_user_profile": "更新用户偏好",
        "memory_os_l2_find_entities": "查找近期记忆实体", "memory_os_l2_find_statements": "查找近期记忆事实", "memory_os_l2_update_entities": "更新近期记忆实体",
        "memory_os_l3_expand_belief": "展开长期记忆", "memory_os_l3_list_domains": "查看记忆领域", "memory_os_l3_update_beliefs": "更新长期记忆",
        "memory_os_l4_find_entity": "查找知识实体", "memory_os_l4_neighbors": "查看实体关系", "memory_os_l4_instances": "查看实体实例",
        "memory_os_l4_update_entities": "更新知识实体", "memory_os_expand_l4": "展开知识图谱", "memory_os_read_record": "读取记忆记录", "memory_os_read_provenance": "查看记忆来源",
        "cloud_kb_recent_context": "查询知识库近期信息", "cloud_kb_knowledge_context": "查询知识库知识", "cloud_kb_read_record": "读取知识库记录",
        "cloud_kb_expand_entity": "展开知识库实体", "cloud_kb_l2_update_entities": "更新知识库近期信息", "cloud_kb_l3_update_knowledge": "更新知识库知识",
        "cloud_kb_l4_update_entities": "更新知识库实体", "cloud_kb_update_relations": "更新知识库关系", "cloud_kb_retract_knowledge": "撤回知识库内容",
        "cloud_kb_validate_publication": "检查知识库发布内容",
        "science_compute": "执行科学计算", "science_units": "换算科学单位", "science_stats": "执行统计分析",
        "science_linalg": "执行线性代数计算", "science_symbolic": "执行符号计算", "science_optimize": "执行数值优化", "science_table_compute": "计算表格数据"
    ]

    public static func displayName(rawToolName: String, semanticKind: AgentToolSemanticKind, fallbackTitle: String? = nil) -> String {
        let normalized = rawToolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "bash", semanticKind != .unknown, semanticKind != .shellCommand {
            return semanticDisplayName(semanticKind)
        }
        if let localized = catalog[normalized] { return localized }
        if semanticKind != .unknown { return semanticDisplayName(semanticKind) }

        let fallback = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fallback.range(of: #"\p{Han}"#, options: .regularExpression) != nil { return fallback }
        if normalized.hasPrefix("mcp__") { return "调用外部工具" }
        if normalized.hasPrefix("memory_os_") { return "执行记忆操作" }
        if normalized.hasPrefix("cloud_kb_") { return "执行知识库操作" }
        if normalized.hasPrefix("mail_") { return "执行邮件操作" }
        if normalized.hasPrefix("rss_") { return "执行 RSS 操作" }
        if normalized.hasPrefix("calendar_") { return "执行日历操作" }
        if normalized.hasPrefix("contact") { return "执行联系人操作" }
        if normalized.hasPrefix("browser_") || normalized.hasPrefix("web_") { return "执行网页操作" }
        if normalized.hasPrefix("science_") { return "执行科学计算" }
        if normalized.hasPrefix("session_") { return "执行会话操作" }
        if normalized.hasPrefix("tasks_") { return "执行任务操作" }
        if normalized.hasPrefix("connor_skill_") { return "执行技能操作" }
        return "执行工具操作"
    }

    private static func semanticDisplayName(_ semanticKind: AgentToolSemanticKind) -> String {
        switch semanticKind {
        case .readFile: return "读取文件"
        case .writeFile: return "写入文件"
        case .editFile: return "编辑文件"
        case .listDirectory: return "查看目录"
        case .findFiles: return "查找文件"
        case .searchFiles: return "搜索文件内容"
        case .shellCommand: return "执行终端命令"
        case .swiftBuild: return "编译 Swift 项目"
        case .swiftTest: return "运行 Swift 测试"
        case .swiftRun: return "运行 Swift 目标"
        case .xcodeBuild: return "编译 Xcode 项目"
        case .git: return "执行 Git 操作"
        case .packageManager: return "管理项目依赖"
        case .python: return "运行 Python 脚本"
        case .node: return "运行 JavaScript 工具"
        case .browser: return "浏览网页"
        case .calendar: return "操作日历"
        case .mcp: return "调用外部工具"
        case .unknown: return "执行工具操作"
        }
    }
}

public struct AgentToolActivityPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var callID: String
    public var phase: AgentToolActivityPhase
    public var rawToolName: String
    public var semanticKind: AgentToolSemanticKind
    public var title: String
    public var subtitle: String?
    public var target: String?
    public var detail: String?
    public var icon: String
    public var severity: AgentEventPresentationSeverity
    public var argumentsJSON: String?
    public var resultJSON: String?

    public init(
        id: String = UUID().uuidString,
        callID: String,
        phase: AgentToolActivityPhase,
        rawToolName: String,
        semanticKind: AgentToolSemanticKind,
        title: String,
        subtitle: String? = nil,
        target: String? = nil,
        detail: String? = nil,
        icon: String,
        severity: AgentEventPresentationSeverity,
        argumentsJSON: String? = nil,
        resultJSON: String? = nil
    ) {
        self.id = id
        self.callID = callID
        self.phase = phase
        self.rawToolName = rawToolName
        self.semanticKind = semanticKind
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.detail = detail
        self.icon = icon
        self.severity = severity
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
    }
}
