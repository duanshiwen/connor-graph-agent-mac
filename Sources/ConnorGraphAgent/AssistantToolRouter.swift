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
        "interactive_web_records_summary",
        "interactive_web_export_records"
    ]
    public static let directToolNames = Set<String>(["Shell", "ApplyPatch"])
        .union(interactiveWebDirectToolNames)
    public static let runtimeInternalToolNames = AssistantBootstrapCoordinator.internalToolNames
        .union(AssistantAttentionCoordinator.internalToolNames)
        .union([AgentCurrentTimePreflightPolicy.requiredToolName])

    public init() {}

    public static let namespaceDescriptors: [AssistantToolNamespaceDescriptor] = [
        .init(name: "calendar", summary: "calendar events, agendas, availability, and changes / 日历、日程、会议与行程", aliases: ["calendar", "event", "agenda", "schedule", "meeting", "日历", "日程", "会议", "行程", "安排"]),
        .init(name: "mail", summary: "mail accounts, recent messages, message details, drafts, and sending / 邮件、邮箱与收件箱", aliases: ["mail", "email", "inbox", "message", "邮件", "邮箱", "收件箱"]),
        .init(name: "rss", summary: "RSS sources, feeds, recent articles, and item details / RSS、订阅源与文章", aliases: ["rss", "feed", "subscription", "订阅", "订阅源", "信息源"]),
        .init(name: "session", summary: "session status and session listings / 会话状态与会话列表", aliases: ["session", "conversation", "chat", "会话", "对话", "聊天", "活动记录"]),
        .init(name: "note", summary: "Note search and full Note reads / 笔记与便签", aliases: ["note", "notes", "notebook", "笔记", "便签", "备忘"]),
        .init(name: "task", summary: "tasks, schedules, and task lifecycle operations / 任务、待办与计划", aliases: ["task", "tasks", "todo", "checklist", "任务", "待办", "清单"]),
        .init(name: "contact", summary: "contacts and person records / 联系人与通讯录", aliases: ["contact", "contacts", "person", "people", "联系人", "通讯录"]),
        .init(name: "browser", summary: "interactive browser navigation and page inspection / 浏览器页面操作", aliases: ["browser", "page", "website", "浏览器", "网页", "网站"]),
        .init(name: "web", summary: "web search and web content retrieval / 网络搜索与网页读取", aliases: ["web", "online", "internet", "联网", "上网", "网络", "查资料"]),
        .init(name: "memory", summary: "Memory OS records and durable knowledge / 记忆与长期知识", aliases: ["memory", "remember", "history", "记忆", "回忆", "历史"]),
        .init(name: "science", summary: "scientific calculation, statistics, linear algebra, units, and optimization / 科学计算、统计、线性代数、单位与优化", aliases: ["science", "compute", "calculation", "statistics", "math", "科学", "计算", "统计", "数学", "公式"]),
        .init(name: "image", summary: "image search, generation, editing, and presentation / 图片搜索、生成、编辑与展示", aliases: ["image", "photo", "picture", "illustration", "图片", "图像", "照片", "配图"]),
        .init(name: "environment", summary: "current environment, location, and weather context / 当前环境、位置与天气", aliases: ["environment", "location", "weather", "环境", "位置", "地点", "天气"]),
        .init(name: "skill", summary: "installed skills and reusable workflows / 已安装技能与工作流", aliases: ["skill", "workflow", "技能", "工作流"]),
        .init(name: "graph", summary: "knowledge graph search and graph-backed records / 知识图谱搜索与图谱记录", aliases: ["graph", "knowledge graph", "图谱", "知识图谱"]),
        .init(name: "workspace", summary: "workspace files, search, and local editing / 工作区文件、搜索与编辑", aliases: ["workspace", "local files", "code", "工作区", "本地文件", "代码", "文件"]),
        .init(name: "knowledge", summary: "cloud knowledge-base search and retrieval / 云端知识库搜索与读取", aliases: ["knowledge", "knowledge base", "cloud knowledge", "知识", "知识库", "云知识库"])
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
        return AssistantToolRoute(
            modelVisibleDefinitions: (AssistantDecisionToolContract.definitions + direct).sorted { $0.name < $1.name },
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
        let terms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 }
        let requestedNamespaces = matchingNamespaces(in: normalizedQuery)
        let matchedNamespaces = requestedNamespaces
            .filter { availableNamespaces.contains($0.name) }
        let matchedNamespaceNames = Set(matchedNamespaces.map(\.name))
        let ranked = candidates.compactMap { definition -> (definition: AgentToolDefinition, score: Int, namespace: String)? in
            let namespace = familyName(for: definition)
            let haystack = normalize("\(definition.name) \(definition.description)")
            var score = terms.reduce(0) { $0 + (haystack.contains($1) ? 2 : 0) }
            if haystack.contains(normalizedQuery), !normalizedQuery.isEmpty { score += 4 }
            if definition.name.lowercased().contains(normalizedQuery), !normalizedQuery.isEmpty { score += 8 }
            if matchedNamespaceNames.contains(namespace) {
                score += 20
                score += preferredOperationScore(
                    toolName: definition.name.lowercased(),
                    namespace: namespace,
                    query: normalizedQuery
                )
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
            guard selected.count < limit,
                  let best = sorted.first(where: { $0.namespace == namespace.name }) else { continue }
            selected.append(best.definition)
            selectedNames.insert(best.definition.name)
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
            ("time_", "science"),
            ("get_current_environment", "environment"),
            ("environment_", "environment"),
            ("connor_skill_", "skill"),
            ("generate_image", "image"),
            ("edit_image", "image"),
            ("present_image", "image"),
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
        let hasRecentWindow = ["today", "recent", "latest", "upcoming", "今天", "今日", "最近", "近期", "近两日", "小时", "每日简报"]
            .contains(where: query.contains)
        guard hasRecentWindow else { return 0 }
        switch namespace {
        case "calendar": return toolName.contains("upcoming") ? 8 : (toolName.contains("search") ? 4 : 0)
        case "mail": return toolName.contains("list_recent") ? 8 : (toolName.contains("search") ? 4 : 0)
        case "rss": return toolName.contains("search_items") ? 8 : (toolName.contains("list_items") ? 4 : 0)
        case "session": return toolName.contains("list_by_status") ? 8 : (toolName.contains("list") ? 4 : 0)
        default: return 0
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
