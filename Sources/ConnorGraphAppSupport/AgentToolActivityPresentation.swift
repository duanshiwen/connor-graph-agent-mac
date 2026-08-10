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
    case parallelQuery
    case batchExecution
    case unknown
}

public enum AgentToolDisplayNameResolver {
    private static let catalog: [String: String] = [
        "read": "读取文件", "ls": "查看目录", "glob": "查找文件", "grep": "搜索文件内容",
        "bash": "执行终端命令", "write": "写入文件", "edit": "编辑文件", "multiedit": "批量编辑文件",
        "get_current_time": "获取当前时间", "time_analyze_ranges": "分析时间范围",
        "graph_search": "搜索知识图谱", "web_search": "搜索网页", "web_fetch": "读取网页内容",
        "note_search": "搜索笔记", "note_get": "读取笔记详情",
        "browser_history_search": "搜索浏览历史", "browser_history_get": "读取浏览记录",
        "generate_image": "生成图片", "edit_image": "编辑图片", "image_search": "搜索图片", "present_image": "载入图片",
        "connor_skill_activate": "启用技能", "connor_skill_list": "查看可用技能", "skill_list": "查看可用技能",
        "connor_skill_create": "创建技能", "connor_skill_update": "更新技能", "connor_skill_delete": "删除技能",
        "session_get_status": "查看会话状态", "session_set_status": "更新会话状态", "session_list_statuses": "查看可用会话状态",
        "personality_get_current": "查看康纳同学性格", "personality_propose_update": "生成人格变更提议", "personality_commit_proposal": "应用人格变更",
        "tasks_list": "查看任务", "tasks_create_scheduled_session_message": "创建定时会话任务", "tasks_create_session_status_message": "创建状态触发任务", "tasks_update_scheduled_session_message": "修改定时会话任务", "tasks_delete": "删除任务",
        "contact_search": "搜索联系人", "contact_create_draft": "创建联系人草稿", "contact_commit_draft": "保存联系人",
        "contacts_read": "读取联系人", "contacts_write": "更新联系人",
        "calendar_search_events": "搜索日程", "calendar_read": "读取日历", "calendar_write": "更新日历",
        "mail_list_accounts": "查看邮箱账户", "mail_search_messages": "搜索邮件", "mail_list_recent_messages": "查看近期邮件",
        "mail_search_messages_with_body_preview": "搜索邮件正文", "mail_list_recent_messages_with_body_preview": "查看近期邮件正文",
        "mail_get_message": "读取邮件", "mail_set_read_state": "更新邮件阅读状态", "mail_create_draft": "创建邮件草稿", "mail_send_draft": "发送邮件",
        "rss_list_sources": "查看 RSS 订阅源", "rss_add_source": "添加 RSS 订阅源", "rss_update_source": "修改 RSS 订阅源", "rss_remove_source": "删除 RSS 订阅源", "rss_sync_source": "同步 RSS 订阅源",
        "rss_list_items": "查看 RSS 文章", "rss_search_items": "搜索 RSS 文章", "rss_get_item": "读取 RSS 文章",
        "rss_set_read_state": "更新 RSS 阅读状态", "rss_set_star_state": "更新 RSS 收藏状态", "rss_set_hidden_state": "更新 RSS 隐藏状态",
        "rss_import_opml": "导入 RSS 订阅", "rss_export_opml": "导出 RSS 订阅", "rss_create_evidence_candidate": "保存 RSS 证据",
        "memory_os_recent_context": "查询近期记忆", "memory_os_knowledge_context": "查询长期记忆", "memory_os_search": "搜索记忆",
        "memory_os_get_current_user_profile": "读取用户偏好", "memory_os_update_current_user_profile": "更新用户偏好",
        "memory_os_l2_find_entities": "查找近期记忆实体", "memory_os_l2_find_statements": "查找近期记忆事实", "memory_os_l2_update_entities": "更新近期记忆实体",
        "memory_os_l3_expand_belief": "展开长期记忆", "memory_os_l3_list_domains": "查看记忆领域", "memory_os_l3_update_beliefs": "更新长期记忆",
        "memory_os_l4_find_entity": "查找知识实体", "memory_os_l4_neighbors": "查看实体关系", "memory_os_l4_instances": "查看实体实例",
        "memory_os_l4_update_entities": "更新知识实体", "memory_os_expand_l4": "展开知识图谱", "memory_os_read_record": "读取记忆记录", "memory_os_read_provenance": "查看记忆来源",
        "cloud_kb_recent_context": "查询知识库近期信息", "cloud_kb_knowledge_context": "查询知识库知识", "cloud_kb_read_record": "读取知识库记录",
        "cloud_kb_expand_entity": "展开知识库实体", "cloud_kb_l2_update_entities": "更新知识库近期信息", "cloud_kb_l3_update_knowledge": "更新知识库知识",
        "cloud_kb_l4_update_entities": "更新知识库实体", "cloud_kb_update_relations": "更新知识库关系", "cloud_kb_retract_knowledge": "撤回知识库内容",
        "cloud_kb_validate_publication": "检查知识库发布内容",
        "interactive_web_sdk_usage": "查看互动网页指南", "interactive_web_create_draft": "创建互动网页草稿",
        "interactive_web_get_draft": "读取互动网页草稿", "interactive_web_edit_draft": "编辑互动网页草稿",
        "interactive_web_list_projects": "查看互动网页项目", "interactive_web_get_project": "读取互动网页项目",
        "interactive_web_download_project": "下载互动网页项目", "interactive_web_get_status": "查看互动网页状态",
        "interactive_web_publish": "发布互动网页", "interactive_web_rollback": "回滚互动网页",
        "interactive_web_set_access": "设置互动网页访问权限", "interactive_web_records_summary": "汇总互动网页记录",
        "interactive_web_export_records": "导出互动网页记录", "interactive_web_records_list": "查看互动网页记录",
        "interactive_web_collection_create": "创建互动网页集合",
        "session_search": "搜索历史会话", "assistant_tool_search": "查找工具说明",
        "prepare_final_output": "生成最终答复", "agent_commit_strategy": "提交执行策略",
        "memory_query": "查询记忆", "attention_brief": "汇总关注事项",
        "parallel_tool_query": "并行查询", "parallel_tool_execute": "批量执行",
        "mail_reply_to_message": "回复邮件", "mail_forward_message": "转发邮件",
        "science_compute": "执行科学计算", "science_units": "换算科学单位", "science_stats": "执行统计分析",
        "science_linalg": "执行线性代数计算", "science_symbolic": "执行符号计算", "science_optimize": "执行数值优化", "science_table_compute": "计算表格数据"
    ]

    public static func displayName(rawToolName: String, semanticKind: AgentToolSemanticKind, fallbackTitle: String? = nil) -> String {
        let normalized = rawToolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fallback = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if semanticKind == .parallelQuery || semanticKind == .batchExecution {
            return fallback.isEmpty ? semanticDisplayName(semanticKind) : fallback
        }
        if normalized.hasPrefix("mcp__") { return rawToolName }
        if normalized == "bash", semanticKind != .unknown, semanticKind != .shellCommand {
            return semanticDisplayName(semanticKind)
        }
        if let localized = catalog[normalized] { return localized }
        if semanticKind != .unknown { return semanticDisplayName(semanticKind) }

        if !fallback.isEmpty { return fallback }
        return rawToolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func categoryName(rawToolName: String, semanticKind: AgentToolSemanticKind) -> String {
        switch semanticKind {
        case .readFile, .writeFile, .editFile, .listDirectory, .findFiles, .searchFiles: return "文件"
        case .shellCommand: return "终端"
        case .swiftBuild, .swiftTest, .swiftRun, .xcodeBuild, .git, .packageManager, .python, .node: return "开发工具"
        case .browser: return "网页"
        case .calendar: return "日历"
        case .mcp: return "MCP"
        case .parallelQuery: return "并行查询"
        case .batchExecution: return "批量执行"
        case .unknown:
            let name = rawToolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name.hasPrefix("memory_os_") || name == "memory_query" { return "记忆" }
            if name.hasPrefix("cloud_kb_") { return "知识库" }
            if name.hasPrefix("mail_") { return "邮件" }
            if name.hasPrefix("rss_") { return "RSS" }
            if name.hasPrefix("contact") || name.hasPrefix("person") { return "人际关系" }
            if name.hasPrefix("session_") { return "会话" }
            if name.hasPrefix("tasks_") { return "任务" }
            if name.hasPrefix("connor_skill_") || name.hasPrefix("skill_") { return "技能" }
            if name.hasPrefix("science_") { return "计算" }
            if name.hasPrefix("browser_") || name.hasPrefix("web_") { return "网页" }
            return "其他"
        }
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
        case .parallelQuery: return "并行查询"
        case .batchExecution: return "批量执行"
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
