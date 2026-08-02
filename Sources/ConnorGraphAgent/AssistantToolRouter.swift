import Foundation

public enum AssistantToolTier: String, Codable, Sendable, Equatable {
    case runtimeInternal
    case alwaysVisible
    case discoverable
}

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

public struct AssistantToolRouter: Sendable, Equatable {
    public static let directToolNames: Set<String> = ["Shell", "ApplyPatch"]
    public static let runtimeInternalToolNames = AssistantBootstrapCoordinator.internalToolNames
        .union(AssistantAttentionCoordinator.internalToolNames)

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
        .init(name: "memory", summary: "Memory OS records and durable knowledge / 记忆与长期知识", aliases: ["memory", "remember", "history", "记忆", "回忆", "历史"])
    ]

    public func route(definitions: [AgentToolDefinition]) -> AssistantToolRoute {
        let publicDefinitions = definitions.filter {
            !Self.runtimeInternalToolNames.contains($0.name)
        }
        let direct = publicDefinitions.filter { Self.directToolNames.contains($0.name) }
        let discoverable = publicDefinitions.filter { !Self.directToolNames.contains($0.name) }
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
        let candidates = route(definitions: definitions).discoverableDefinitions
        let normalizedQuery = normalize(query)
        let terms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 }
        let matchedNamespaces = matchingNamespaces(in: normalizedQuery)
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
        guard matchedNamespaces.count > 1 else {
            guard let topScore = sorted.first?.score else { return [] }
            return sorted
                .filter { $0.score >= max(1, topScore - 1) }
                .prefix(limit)
                .map(\.definition)
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
        return selected
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
            "Only direct workspace tools and control tools have stable schemas in this request. For any other capability, call assistant_tool_search once with a compact capability query, then invoke returned exact names and schemas through parallel_tool_query or parallel_tool_execute.",
            "Available families:"
        ] + lines).joined(separator: "\n")
    }

    private func familyName(for definition: AgentToolDefinition) -> String {
        let name = definition.name.lowercased()
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
            description: "Search the current session's approved Tool Registry, MCP, and knowledge capabilities. Returns a small set of exact tool names with complete input schemas. Use once per missing capability and do not repeat the same query.",
            inputSchema: .closedObject(properties: [
                "query": .string(description: "Compact capability or domain query."),
                "maxResults": .integer(description: "Optional result limit from 1 through 16; default 8.")
            ], required: ["query"])
        ),
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalSearchBatchName }!,
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalReadBatchName }!
    ].sorted { $0.name < $1.name }
}
