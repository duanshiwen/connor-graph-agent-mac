import Foundation

public struct AssistantToolRoute: Sendable, Equatable {
    public var modelVisibleDefinitions: [AgentToolDefinition]
    public var discoverableDefinitions: [AgentToolDefinition]

    public init(modelVisibleDefinitions: [AgentToolDefinition], discoverableDefinitions: [AgentToolDefinition]) {
        self.modelVisibleDefinitions = modelVisibleDefinitions
        self.discoverableDefinitions = discoverableDefinitions
    }
}

public struct AssistantToolNamespaceDescriptor: Sendable, Equatable {
    public var name: String
    public var summary: String
    public var aliases: [String]

    public init(name: String, summary: String, aliases: [String]) {
        self.name = name
        self.summary = summary
        self.aliases = aliases
    }
}

public struct AssistantToolDiscoveryResult: Sendable, Equatable {
    public var tools: [AgentToolDefinition]
    public var requestedNamespaces: [String]
    public var matchedNamespaces: [String]
    public var availableNamespaces: [String]

    public init(
        tools: [AgentToolDefinition],
        requestedNamespaces: [String],
        matchedNamespaces: [String],
        availableNamespaces: [String]
    ) {
        self.tools = tools
        self.requestedNamespaces = requestedNamespaces
        self.matchedNamespaces = matchedNamespaces
        self.availableNamespaces = availableNamespaces
    }

    public var unavailableNamespaces: [String] {
        let available = Set(availableNamespaces)
        return requestedNamespaces.filter { !available.contains($0) }
    }
}

public struct AssistantToolRouter: Sendable, Equatable {
    public static let interactiveWebDirectToolNames: Set<String> = [
        "interactive_web_sdk_usage",
        "interactive_web_create_draft",
        "interactive_web_edit_draft",
        "interactive_web_get_draft",
        "interactive_web_get_status",
        "interactive_web_publish",
        "interactive_web_delete_project",
        "interactive_web_records_summary",
        "interactive_web_export_records"
    ]
    public static let directToolNames = Set<String>(["Shell", "ApplyPatch"])
        .union(interactiveWebDirectToolNames)
    // Conversation-time Memory/profile/Note continuity tools are model-driven and
    // therefore discoverable by the model. Only runtime-managed checkpoints and
    // the removed memory_os_search surface stay hidden from the model.
    public static let runtimeInternalToolNames = AssistantAttentionCoordinator.internalToolNames
        .union([AgentCurrentTimePreflightPolicy.requiredToolName])
        .union(["memory_os_search"])

    public init() {}

    public static let namespaceDescriptors: [AssistantToolNamespaceDescriptor] = [
        .init(name: "calendar", summary: "calendar events, agendas, availability, and changes / 日历、日程、会议与行程", aliases: ["calendar", "event", "agenda", "schedule", "meeting", "appointment", "availability", "日历", "日程", "会议", "行程", "安排", "事件", "预约", "排期", "日程安排"]),
        .init(name: "mail", summary: "mail accounts, recent messages, message details, drafts, and sending / 邮件、邮箱与收件箱", aliases: ["mail", "email", "e-mail", "gmail", "outlook", "inbox", "message", "邮件", "邮箱", "收件箱", "电邮", "信件", "发信", "写信"]),
        .init(name: "rss", summary: "RSS sources, feeds, recent articles, and item details / RSS、订阅源与文章", aliases: ["rss", "feed", "subscription", "article", "news", "订阅", "订阅源", "资讯", "新闻", "文章", "信息源"]),
        .init(name: "session", summary: "session status and session listings / 会话状态与会话列表", aliases: ["session", "conversation", "chat", "会话", "对话", "聊天", "活动记录", "交谈"]),
        .init(name: "note", summary: "Note search and full Note reads / 笔记与便签", aliases: ["note", "notes", "notebook", "memo", "笔记", "便签", "备忘", "手记"]),
        .init(name: "task", summary: "tasks, schedules, and task lifecycle operations / 任务、待办与计划", aliases: ["task", "tasks", "todo", "checklist", "reminder", "任务", "待办", "提醒", "清单", "定时", "计划"]),
        .init(name: "contact", summary: "contacts and person records / 联系人与通讯录", aliases: ["contact", "contacts", "person", "people", "联系人", "通讯录", "名片", "人脉"]),
        .init(name: "browser", summary: "interactive browser navigation and page inspection / 浏览器页面操作", aliases: ["browser", "page", "website", "webpage", "浏览器", "网页", "网站", "页面", "浏览", "标签页"]),
        .init(name: "web", summary: "web search and web content retrieval / 网络搜索与网页读取", aliases: ["web", "online", "internet", "联网", "上网", "网络", "查资料"]),
        .init(name: "memory", summary: "Memory OS records and durable knowledge / 记忆与长期知识", aliases: ["memory", "remember", "history", "记忆", "回忆", "历史", "印象", "记得"]),
        .init(name: "science", summary: "scientific calculation, statistics, linear algebra, units, and optimization / 科学计算、统计、线性代数、单位与优化", aliases: ["science", "compute", "calculation", "statistics", "math", "mathematics", "unit", "科学", "计算", "统计", "数学", "公式", "单位", "代数", "方程", "概率"]),
        .init(name: "image", summary: "image search, generation, editing, and presentation / 图片搜索、生成、编辑与展示", aliases: ["image", "photo", "picture", "illustration", "图片", "图像", "照片", "配图", "插图", "绘画"]),
        .init(name: "environment", summary: "current environment, location, and weather context / 当前环境、位置与天气", aliases: ["environment", "location", "weather", "环境", "位置", "地点", "天气", "温度", "时区"]),
        .init(name: "skill", summary: "installed skills and reusable workflows / 已安装技能与工作流", aliases: ["skill", "workflow", "技能", "工作流", "能力"]),
        .init(name: "graph", summary: "knowledge graph search and graph-backed records / 知识图谱搜索与图谱记录", aliases: ["graph", "knowledge graph", "图谱", "知识图谱", "关系图", "实体关系"]),
        .init(name: "workspace", summary: "workspace files, search, local editing, and shell commands / 工作区文件、搜索、编辑与 Shell 命令", aliases: ["workspace", "local files", "code", "file", "write", "save", "export", "patch", "shell", "command", "terminal", "run", "execute", "git", "build", "compile", "工作区", "本地文件", "本地", "代码", "文件", "目录", "文件夹", "项目", "工程", "写", "写入", "导出", "保存", "落盘", "补丁", "修改", "编辑", "执行", "运行", "终端", "命令", "命令行", "构建", "编译", "跑命令", "执行命令", "终端命令", "写文件", "写入文件", "创建文件", "新建文件", "新增文件", "生成文件", "建文件", "改文件", "编辑文件", "修改文件", "更新文件", "保存文件", "删除文件", "移除文件", "文件操作", "文件管理", "增删改", "读写", "存盘", "打补丁"]),
        .init(name: "knowledge", summary: "cloud knowledge-base search and retrieval / 云端知识库搜索与读取", aliases: ["knowledge", "knowledge base", "cloud knowledge", "知识", "知识库", "云知识库", "云端"])
    ]

    public func route(definitions: [AgentToolDefinition]) -> AssistantToolRoute {
        route(initiallyExposedDefinitions: definitions, catalogDefinitions: definitions)
    }

    public func route(
        initiallyExposedDefinitions: [AgentToolDefinition],
        catalogDefinitions: [AgentToolDefinition]
    ) -> AssistantToolRoute {
        let publicExposedDefinitions = initiallyExposedDefinitions.filter {
            !Self.runtimeInternalToolNames.contains($0.name)
        }
        let publicCatalogDefinitions = catalogDefinitions.filter {
            !Self.runtimeInternalToolNames.contains($0.name)
        }
        let direct = publicExposedDefinitions.filter { Self.directToolNames.contains($0.name) }
        let discoverable = publicCatalogDefinitions.filter { !Self.directToolNames.contains($0.name) }
        // 中间过程消息由模型自主调用 share_progress_update 产生：该工具必须对模型直接可见，
        // 不能只放在可发现目录里（否则模型几乎不会发现并调用，中间消息会完全消失）。
        let progressUpdateDefinition = publicCatalogDefinitions.first { $0.name == ShareProgressUpdateTool.toolName }
        let conversationVisible = direct + (progressUpdateDefinition.map { [$0] } ?? [])
        return AssistantToolRoute(
            modelVisibleDefinitions: (AssistantDecisionToolContract.definitions + conversationVisible).sorted { $0.name < $1.name },
            discoverableDefinitions: discoverable.sorted { $0.name < $1.name }
        )
    }

    public func discover(
        query: String,
        definitions: [AgentToolDefinition],
        maximumResults: Int = 8
    ) -> [AgentToolDefinition] {
        discovery(query: query, definitions: definitions, maximumResults: maximumResults).tools
    }

    public func discovery(
        query: String,
        definitions: [AgentToolDefinition],
        maximumResults: Int = 8
    ) -> AssistantToolDiscoveryResult {
        let route = route(definitions: definitions)
        let directDefinitions = definitions.filter { Self.directToolNames.contains($0.name) }
        let candidates = (route.discoverableDefinitions + directDefinitions).sorted { $0.name < $1.name }
        let availableNamespaces = Array(Set(candidates.map { familyName(for: $0) })).sorted()
        let normalizedQuery = normalize(query)
        let queryTerms = tokenize(normalizedQuery).filter { $0.count >= 2 }
        let queryConcepts = concepts(in: normalizedQuery, tokens: queryTerms)
        let requestedNamespaces = matchingNamespaces(in: normalizedQuery)
        let matchedNamespaces = requestedNamespaces
            .filter { availableNamespaces.contains($0.name) }
        let matchedNamespaceNames = Set(matchedNamespaces.map(\.name))
        let ranked = candidates.compactMap { definition -> (definition: AgentToolDefinition, score: Int, namespace: String)? in
            let namespace = familyName(for: definition)
            let normalizedName = normalize(definition.name)
            let normalizedDescription = normalize(definition.description)
            let nameTokens = Set(tokenize(normalizedName))
            let descriptionTokens = Set(tokenize(normalizedDescription))
            let haystack = "\(normalizedName) \(normalizedDescription)"
            var score = 0
            if !normalizedQuery.isEmpty, haystack.contains(normalizedQuery) { score += 4 }
            if !normalizedQuery.isEmpty, normalizedName.contains(normalizedQuery) { score += 8 }
            for term in queryTerms {
                let nameHit = nameTokens.map { tokenMatchScore(queryTerm: term, haystackToken: $0, isName: true) }.max() ?? 0
                let descriptionHit = descriptionTokens.map { tokenMatchScore(queryTerm: term, haystackToken: $0, isName: false) }.max() ?? 0
                score += nameHit + descriptionHit
            }
            let toolConcepts = concepts(in: haystack, tokens: Array(nameTokens.union(descriptionTokens)))
            let semanticOverlap = queryConcepts.intersection(toolConcepts)
            if matchedNamespaceNames.contains(namespace) {
                score += min(semanticOverlap.count, 3)
            } else {
                score += min(semanticOverlap.count, 3) * 3
            }
            if matchedNamespaceNames.contains(namespace) {
                score += 20
                score += preferredOperationScore(
                    toolName: definition.name.lowercased(),
                    namespace: namespace,
                    query: normalizedQuery
                )
                if let preference = operationPreferenceKey(for: normalizedQuery) {
                    score += preferredOperationScore(
                        forPreference: preference,
                        toolName: definition.name.lowercased(),
                        namespace: namespace
                    )
                }
            }
            return score > 0 ? (definition, score, namespace) : nil
        }
        let sorted = ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.definition.name < $1.definition.name
        }
        let limit = max(1, min(maximumResults, 16))
        let tools: [AgentToolDefinition]
        guard matchedNamespaces.count > 1 else {
            if let topScore = sorted.first?.score {
                tools = Array(sorted
                    .filter { $0.score >= max(1, topScore - 1) }
                    .prefix(limit)
                    .map(\.definition))
            } else {
                tools = []
            }
            return AssistantToolDiscoveryResult(
                tools: tools,
                requestedNamespaces: requestedNamespaces.map(\.name),
                matchedNamespaces: matchedNamespaces.map(\.name),
                availableNamespaces: availableNamespaces
            )
        }

        var selected: [AgentToolDefinition] = []
        var selectedNames = Set<String>()
        for namespace in matchedNamespaces {
            guard selected.count < limit else { break }
            let namespaceItems = sorted.filter { $0.namespace == namespace.name }
            let take = min(2, namespaceItems.count, limit - selected.count)
            for item in namespaceItems.prefix(take) {
                selected.append(item.definition)
                selectedNames.insert(item.definition.name)
            }
        }
        for item in sorted where selected.count < limit && !selectedNames.contains(item.definition.name) {
            selected.append(item.definition)
            selectedNames.insert(item.definition.name)
        }
        return AssistantToolDiscoveryResult(
            tools: selected,
            requestedNamespaces: requestedNamespaces.map(\.name),
            matchedNamespaces: matchedNamespaces.map(\.name),
            availableNamespaces: availableNamespaces
        )
    }

    public func compactCatalogSummary(definitions: [AgentToolDefinition]) -> String {
        let discoverable = route(definitions: definitions).discoverableDefinitions
        let families = Dictionary(grouping: discoverable, by: familyName(for:))
        let lines = families.keys.sorted().map { family in
            let summary = Self.namespaceDescriptors.first { $0.name == family }?.summary
                ?? "tools in the \(family) namespace"
            return "- \(family): \(summary); \(families[family]?.count ?? 0) tools"
        }
        return ([
            "## Tool Discovery",
            "Direct workspace tools, core interactive webpage tools, and control tools have stable schemas in this request. assistant_tool_search discovers schemas only; it does not read data. For any other capability, search once using one or more compact capability domains in the user's language, then invoke returned exact names and schemas through parallel_tool_query or parallel_tool_execute. Keep dates, record IDs, and operation arguments for the native tool call.",
            "Discovery tips: put the operation and the domain together and try synonyms in both languages, e.g. \"写文件 / 执行命令 / 运行 / 终端 / shell / git / 构建 / 测试\". If one phrasing returns nothing, re-search with synonyms rather than inventing a tool name. Workspace file changes are the direct ApplyPatch tool; shell commands are the direct Shell tool.",
            "Available families:"
        ] + lines).joined(separator: "\n")
    }

    private func familyName(for definition: AgentToolDefinition) -> String {
        let name = definition.name.lowercased()
        if ["read", "readmany", "edit", "multiedit", "write", "glob", "grep", "ls", "shell", "applypatch"].contains(name) {
            return "workspace"
        }
        let mappedPrefixes: [(prefix: String, family: String)] = [
            ("contacts_", "contact"),
            ("person_", "contact"),
            ("tasks_", "task"),
            ("time_", "science"),
            ("get_current_environment", "environment"),
            ("environment_", "environment"),
            ("connor_skill_", "skill"),
            ("generate_image", "image"),
            ("edit_image", "image"),
            ("present_image", "image"),
            ("session_search", "memory"),
            ("local_", "workspace"),
            ("workspace_", "workspace"),
            ("cloud_kb_", "knowledge")
        ]
        if let mapping = mappedPrefixes.first(where: { name.hasPrefix($0.prefix) }) {
            return mapping.family
        }
        if let separator = name.firstIndex(of: "_") { return String(name[..<separator]) }
        return name
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchingNamespaces(in query: String) -> [AssistantToolNamespaceDescriptor] {
        Self.namespaceDescriptors.compactMap { descriptor in
            descriptor.aliases.contains(where: { query.contains(normalize($0)) }) ? descriptor : nil
        }
    }

    private func preferredOperationScore(toolName: String, namespace: String, query: String) -> Int {
        let hasRecentWindow = ["today", "recent", "latest", "upcoming", "yesterday", "tomorrow", "daily",
                               "今天", "今日", "今晚", "最近", "近期", "近两日", "近48", "小时", "每日", "每天",
                               "昨天", "明日", "明天", "本周", "上周", "下周", "未来", "过去", "近"]
            .contains(where: query.contains)
        guard hasRecentWindow else { return 0 }
        switch namespace {
        case "calendar": return toolName.contains("upcoming") ? 8 : (toolName.contains("search") ? 4 : 0)
        case "mail": return toolName.contains("list_recent") ? 8 : (toolName.contains("search") ? 4 : 0)
        case "rss": return toolName.contains("search_items") ? 8 : (toolName.contains("list_items") ? 4 : 0)
        case "session": return toolName.contains("list_by_status") ? 8 : (toolName.contains("list") ? 4 : 0)
        case "memory": return toolName.contains("recent_context") ? 8 : (toolName.contains("search") ? 4 : 0)
        default: return 0
        }
    }

    private func preferredOperationScore(forPreference key: String, toolName: String, namespace: String) -> Int {
        switch key {
        case "create":
            switch namespace {
            case "task": return toolName.contains("create") ? 8 : 0
            case "note": return toolName.contains("create") ? 8 : 0
            case "mail": return toolName.contains("create_draft") ? 8 : (toolName.contains("send_draft") ? 6 : 0)
            case "calendar": return toolName.contains("write") ? 8 : 0
            case "contact": return toolName.contains("create") ? 8 : 0
            case "rss": return toolName.contains("add_source") ? 8 : 0
            case "skill": return toolName.contains("create") ? 8 : 0
            case "image": return (toolName.contains("generate") || toolName.contains("create")) ? 8 : 0
            case "workspace": return (toolName == "write" || toolName == "applypatch") ? 8 : ((toolName == "edit" || toolName == "multiedit") ? 6 : 0)
            default: return 0
            }
        case "delete":
            switch namespace {
            case "task": return toolName.contains("delete") ? 8 : 0
            case "note": return toolName.contains("delete") ? 8 : 0
            case "rss": return toolName.contains("remove_source") ? 8 : 0
            case "skill": return toolName.contains("delete") ? 8 : 0
            case "workspace": return toolName == "applypatch" ? 8 : 0
            default: return 0
            }
        case "run":
            switch namespace {
            case "workspace": return toolName == "shell" ? 8 : 0
            default: return 0
            }
        case "edit":
            switch namespace {
            case "workspace": return (toolName == "edit" || toolName == "multiedit" || toolName == "applypatch") ? 8 : 0
            case "note": return toolName.contains("edit") ? 8 : 0
            case "rss": return toolName.contains("update_source") ? 8 : 0
            case "contact": return toolName.contains("update") ? 8 : 0
            default: return 0
            }
        case "list":
            switch namespace {
            case "task": return toolName.contains("list") ? 6 : 0
            case "session": return toolName.contains("list") ? 6 : 0
            case "skill": return toolName.contains("list") ? 6 : 0
            case "contact": return (toolName.contains("list") || toolName.contains("read")) ? 4 : 0
            case "mail": return toolName.contains("list") ? 4 : 0
            case "calendar": return (toolName.contains("search") || toolName.contains("upcoming")) ? 4 : 0
            case "rss": return toolName.contains("list") ? 4 : 0
            default: return 0
            }
        case "search":
            switch namespace {
            case "mail", "rss", "note", "contact", "memory", "session", "browser", "web", "workspace", "knowledge", "graph", "calendar":
                return toolName.contains("search") ? 6 : ((toolName.contains("find") || toolName.contains("glob") || toolName.contains("grep")) ? 4 : 0)
            default: return 0
            }
        case "read":
            switch namespace {
            case "workspace": return (toolName == "read" || toolName == "readmany") ? 8 : (toolName == "ls" ? 4 : 0)
            case "note": return toolName.contains("get") ? 8 : 0
            case "web": return toolName.contains("fetch") ? 8 : 0
            case "contact": return (toolName.contains("get") || toolName.contains("read")) ? 6 : 0
            case "mail": return toolName.contains("get_message") ? 8 : 0
            case "rss": return toolName.contains("get_item") ? 8 : 0
            default: return 0
            }
        default:
            return 0
        }
    }

    private func operationPreferenceKey(for query: String) -> String? {
        let create = ["create", "add", "new", "compose", "send", "schedule", "draft", "创建", "新建", "添加", "新增", "发送", "撰写", "写", "生成", "定时", "提醒", "计划", "写文件", "写入文件", "创建文件", "新建文件", "新增文件", "生成文件", "建文件", "保存", "保存文件"]
        if containsAny(in: query, create) { return "create" }
        let delete = ["delete", "remove", "取消", "删除", "移除", "删", "删除文件", "移除文件"]
        if containsAny(in: query, delete) { return "delete" }
        let edit = ["edit", "update", "modify", "change", "patch", "编辑", "修改", "更新", "更改", "改动", "改", "变更", "补丁", "打补丁", "改文件", "编辑文件", "修改文件", "更新文件"]
        if containsAny(in: query, edit) { return "edit" }
        let run = ["run", "execute", "exec", "shell", "command", "terminal", "cli", "git", "build", "compile", "执行", "运行", "终端", "命令", "命令行", "构建", "编译", "跑", "跑命令", "跑测试", "执行命令", "终端命令"]
        if containsAny(in: query, run) { return "run" }
        let list = ["list", "show", "display", "status", "列表", "列出", "查看", "显示", "状态", "有多少"]
        if containsAny(in: query, list) { return "list" }
        let search = ["search", "find", "query", "lookup", "检索", "搜索", "查找", "查询", "找"]
        if containsAny(in: query, search) { return "search" }
        let read = ["read", "get", "fetch", "open", "view", "detail", "inspect", "读取", "获取", "详情", "打开", "预览", "看", "读", "读文件"]
        if containsAny(in: query, read) { return "read" }
        return nil
    }

    private func containsAny(in text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private struct SemanticConcept: Sendable {
        let name: String
        let forms: [String]

        init(_ name: String, _ forms: [String]) {
            self.name = name
            self.forms = forms
        }
    }

    private static let semanticConcepts: [SemanticConcept] = [
        .init("mail", ["mail", "email", "gmail", "outlook", "inbox", "message", "letter", "邮件", "邮箱", "收件箱", "电邮", "信件", "发信", "写信"]),
        .init("calendar", ["calendar", "event", "agenda", "schedule", "appointment", "meeting", "日历", "日程", "会议", "行程", "事件", "预约", "安排", "排期"]),
        .init("rss", ["rss", "feed", "subscription", "article", "news", "订阅", "订阅源", "资讯", "新闻", "文章", "信息源"]),
        .init("task", ["task", "todo", "reminder", "checklist", "deadline", "任务", "待办", "提醒", "清单", "定时", "截止", "计划"]),
        .init("note", ["note", "memo", "notebook", "笔记", "便签", "备忘", "手记", "摘记"]),
        .init("contact", ["contact", "person", "people", "address", "联系人", "通讯录", "名片", "人脉", "通讯"]),
        .init("browser", ["browser", "webpage", "website", "page", "tab", "浏览器", "网页", "网站", "页面", "标签页", "浏览"]),
        .init("web", ["web", "online", "internet", "network", "网络", "联网", "上网", "在线", "互联网"]),
        .init("search", ["search", "find", "query", "lookup", "retrieve", "搜索", "查找", "查询", "检索", "找"]),
        .init("recent", ["recent", "latest", "today", "upcoming", "new", "最近", "最新", "今日", "今天", "即将", "近期", "近"]),
        .init("memory", ["memory", "remember", "history", "记忆", "回忆", "历史", "记得", "印象"]),
        .init("science", ["science", "math", "mathematics", "statistics", "compute", "calculate", "calculation", "unit", "科学", "数学", "统计", "计算", "公式", "单位", "方程", "概率", "代数", "线性", "算"]),
        .init("image", ["image", "photo", "picture", "illustration", "icon", "图片", "图像", "照片", "配图", "插图", "绘画", "画"]),
        .init("environment", ["environment", "location", "weather", "temperature", "环境", "位置", "地点", "天气", "温度", "时区"]),
        .init("skill", ["skill", "workflow", "capability", "技能", "工作流", "能力"]),
        .init("graph", ["graph", "knowledge", "relation", "entity", "图谱", "知识图谱", "关系", "实体"]),
        .init("workspace", ["workspace", "file", "folder", "directory", "code", "project", "local", "write", "save", "export", "patch", "工作区", "文件", "文件夹", "目录", "代码", "项目", "本地", "写", "写入", "导出", "保存", "落盘", "补丁", "修改", "编辑", "写文件", "写入文件", "创建文件", "新建文件", "新增文件", "生成文件", "建文件", "改文件", "编辑文件", "修改文件", "更新文件", "保存文件", "删除文件", "移除文件", "文件操作", "文件管理", "增删改", "读写", "存盘", "打补丁"]),
        .init("shell", ["shell", "terminal", "command", "cli", "console", "bash", "zsh", "终端", "命令", "命令行", "控制台"]),
        .init("run", ["run", "execute", "exec", "执行", "运行", "跑", "跑命令", "跑测试", "执行命令"]),
        .init("git", ["git", "version control", "version-control", "仓库", "版本控制"]),
        .init("session", ["session", "conversation", "chat", "会话", "对话", "聊天", "交谈"]),
        .init("send", ["send", "compose", "draft", "reply", "forward", "发送", "撰写", "回复", "转发"]),
        .init("read", ["read", "view", "open", "get", "detail", "inspect", "读取", "查看", "打开", "获取", "详情", "预览", "看"]),
        .init("create", ["create", "add", "new", "schedule", "generate", "创建", "新建", "添加", "新增", "生成", "制作"]),
        .init("list", ["list", "enumerate", "列表", "列举", "列出"]),
        .init("edit", ["edit", "update", "modify", "delete", "remove", "编辑", "修改", "更新", "删除", "移除", "更改"]),
        .init("time", ["time", "date", "day", "hour", "week", "month", "时间", "日期", "小时", "周", "月", "天"])
    ]

    private func concepts(in text: String, tokens: [String]) -> Set<String> {
        var matched = Set<String>()
        for concept in Self.semanticConcepts {
            for form in concept.forms {
                let normalizedForm = normalize(form)
                if normalizedForm.containsCJKCharacter {
                    if text.contains(normalizedForm) {
                        matched.insert(concept.name)
                        break
                    }
                } else if tokens.contains(normalizedForm)
                    || tokens.contains(where: { stem($0) == stem(normalizedForm) }) {
                    matched.insert(concept.name)
                    break
                }
            }
        }
        return matched
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var latin: [Character] = []
        var cjkRun: [Character] = []

        func flushLatin() {
            if !latin.isEmpty {
                tokens.append(String(latin))
                latin.removeAll(keepingCapacity: true)
            }
        }

        func flushCJK() {
            if cjkRun.count >= 2 {
                for index in 0..<(cjkRun.count - 1) {
                    tokens.append(String(cjkRun[index...index + 1]))
                }
            }
            cjkRun.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.isASCII, character.isLetter || character.isNumber {
                flushCJK()
                latin.append(character)
            } else if character.isCJKCharacter {
                flushLatin()
                cjkRun.append(character)
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()
        return tokens
    }

    private func stem(_ token: String) -> String {
        var value = token
        if value.count > 5, value.hasSuffix("ing") {
            value = String(value.dropLast(3))
        } else if value.count > 4, value.hasSuffix("ies") {
            value = String(value.dropLast(3)) + "y"
        } else if value.count > 4, value.hasSuffix("es") {
            value = String(value.dropLast(2))
        } else if value.count > 4, value.hasSuffix("s"),
                  !value.hasSuffix("ss"), !value.hasSuffix("us"), !value.hasSuffix("is") {
            value = String(value.dropLast())
        }
        return value
    }

    private func tokenMatchScore(queryTerm: String, haystackToken: String, isName: Bool) -> Int {
        if queryTerm == haystackToken { return isName ? 6 : 2 }
        if stem(queryTerm) == stem(haystackToken) { return isName ? 4 : 1 }
        if queryTerm.count >= 4, haystackToken.hasPrefix(queryTerm) { return isName ? 4 : 1 }
        if haystackToken.count >= 4, queryTerm.hasPrefix(haystackToken) { return isName ? 3 : 1 }
        if queryTerm.count >= 5, haystackToken.count >= 5,
           levenshteinDistance(queryTerm, haystackToken, maximum: 1) != nil {
            return isName ? 3 : 1
        }
        if queryTerm.count >= 6, haystackToken.count >= 6,
           levenshteinDistance(queryTerm, haystackToken, maximum: 2) != nil {
            return isName ? 2 : 1
        }
        return 0
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String, maximum: Int) -> Int? {
        let a = Array(lhs)
        let b = Array(rhs)
        guard abs(a.count - b.count) <= maximum else { return nil }
        if a == b { return 0 }
        var previous = Array(0...b.count)
        for (index, left) in a.enumerated() {
            var current = [index + 1]
            var rowMinimum = current[0]
            for (j, right) in b.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                let insertion = previous[j + 1] + 1
                let deletion = current[j] + 1
                let value = min(substitution, insertion, deletion)
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maximum { return nil }
            previous = current
        }
        let distance = previous[b.count]
        return distance <= maximum ? distance : nil
    }
}

private extension Character {
    var isCJKCharacter: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        let value = scalar.value
        return (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
    }
}

private extension String {
    var containsCJKCharacter: Bool {
        unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
        }
    }
}

public enum AssistantDecisionToolContract {
    public static let searchName = "assistant_tool_search"

    public static let definitions: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: searchName,
            description: "Discover callable capabilities in the current session's approved Tool Registry, MCP, and knowledge catalog. This returns exact tool names and complete input schemas but never reads source data or performs an action. The query may name one or more capability domains in the user's language. Use once for the missing domains, then call the returned native tools; do not repeat the same discovery query.",
            inputSchema: .closedObject(properties: [
                "query": .string(description: "One or more compact capability domains in the user's language. Keep dates, record IDs, and operation arguments for the returned native tool calls."),
                "maxResults": .integer(description: "Optional result limit from 1 through 16; default 8.")
            ], required: ["query"])
        ),
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalSearchBatchName }!,
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalReadBatchName }!
    ].sorted { $0.name < $1.name }
}
