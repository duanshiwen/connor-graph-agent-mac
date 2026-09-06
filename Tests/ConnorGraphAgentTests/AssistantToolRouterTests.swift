import Testing
@testable import ConnorGraphAgent

@Test func toolRouterExposesModelDrivenContinuityToolsAndKeepsControlSurfaceStable() {
    let definitions = [
        AgentToolDefinition(name: "memory_os_recent_context", description: "memory", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "memory_os_knowledge_context", description: "knowledge", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "memory_os_get_current_user_profile", description: "profile", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "note_search", description: "notes", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "memory_os_search", description: "removed search surface", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Shell", description: "Run shell", inputSchema: .object(properties: [:], required: []))
    ]

    let route = AssistantToolRouter().route(definitions: definitions)

    #expect(route.discoverableDefinitions.contains { $0.name == "memory_os_recent_context" })
    #expect(route.discoverableDefinitions.contains { $0.name == "memory_os_knowledge_context" })
    #expect(route.discoverableDefinitions.contains { $0.name == "memory_os_get_current_user_profile" })
    #expect(route.discoverableDefinitions.contains { $0.name == "note_search" })
    #expect(!route.discoverableDefinitions.contains { $0.name == "memory_os_search" })
    #expect(route.modelVisibleDefinitions.contains { $0.name == "Shell" })
    #expect(route.modelVisibleDefinitions.contains { $0.name == AssistantDecisionToolContract.searchName })
    #expect(!route.modelVisibleDefinitions.contains { $0.name == "mail_search_messages" })
}

@Test func toolRouterExposesCoreInteractiveWebWorkflowWithoutDiscovery() {
    let definitions = [
        "interactive_web_sdk_usage",
        "interactive_web_create_draft",
        "interactive_web_edit_draft",
        "interactive_web_get_draft",
        "interactive_web_get_status",
        "interactive_web_publish",
        "interactive_web_delete_project",
        "interactive_web_records_summary",
        "interactive_web_export_records",
        "interactive_web_offline"
    ].map {
        AgentToolDefinition(name: $0, description: $0, inputSchema: .object(properties: [:], required: []))
    }

    let route = AssistantToolRouter().route(definitions: definitions)
    let visibleNames = Set(route.modelVisibleDefinitions.map(\.name))

    #expect(AssistantToolRouter.interactiveWebDirectToolNames.isSubset(of: visibleNames))
    #expect(!visibleNames.contains("interactive_web_offline"))
    #expect(route.discoverableDefinitions.contains { $0.name == "interactive_web_offline" })
}

@Test func toolRouterKeepsProgressUpdateDirectlyVisibleToTheModel() {
    let definitions = [
        AgentToolDefinition(name: "Shell", description: "Run shell", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: ShareProgressUpdateTool.toolName, description: "Progress update", inputSchema: .object(properties: [:], required: []))
    ]

    let route = AssistantToolRouter().route(definitions: definitions)

    #expect(route.modelVisibleDefinitions.contains { $0.name == ShareProgressUpdateTool.toolName })
    #expect(route.discoverableDefinitions.contains { $0.name == ShareProgressUpdateTool.toolName })
}

@Test func toolRouterKeepsTheCompleteCatalogDiscoverableWithoutExpandingTheStableSurface() {
    let exposedDefinitions = [
        AgentToolDefinition(name: "Shell", description: "Run shell", inputSchema: .object(properties: [:], required: []))
    ]
    let catalogDefinitions = exposedDefinitions + [
        AgentToolDefinition(name: "web_search", description: "Search the public web", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "get_current_time", description: "Internal time preflight", inputSchema: .object(properties: [:], required: []))
    ]

    let route = AssistantToolRouter().route(
        initiallyExposedDefinitions: exposedDefinitions,
        catalogDefinitions: catalogDefinitions
    )

    #expect(route.modelVisibleDefinitions.contains { $0.name == "Shell" })
    #expect(!route.modelVisibleDefinitions.contains { $0.name == "web_search" })
    #expect(route.discoverableDefinitions.contains { $0.name == "web_search" })
    #expect(!route.discoverableDefinitions.contains { $0.name == "get_current_time" })
}

@Test func toolSearchReturnsRelevantFullSchemasOnly() {
    let definitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: ["query": .string(description: "query")], required: ["query"])),
        AgentToolDefinition(name: "calendar_search_events", description: "Search calendar events", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "email search", definitions: definitions)

    #expect(matches.map(\.name) == ["mail_search_messages"])
    #expect(matches.first?.inputSchema.jsonObject["properties"] != nil)
}

@Test func toolSearchCanRecoverDirectWorkspaceToolSchemas() {
    let definitions = [
        AgentToolDefinition(name: "Shell", description: "Inspect and search workspace files", inputSchema: .closedObject(properties: ["command": .string(description: "Command")], required: ["command"])),
        AgentToolDefinition(name: "ApplyPatch", description: "Edit workspace files", inputSchema: .closedObject(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .closedObject(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(query: "本地文件读取工具", definitions: definitions)

    #expect(Set(result.tools.map(\.name)) == ["Shell", "ApplyPatch"])
    #expect(result.matchedNamespaces == ["workspace"])
    #expect(result.availableNamespaces.contains("workspace"))
}

@Test func toolSearchMatchesChineseAndMixedLanguageQueries() {
    let definitions = [
        AgentToolDefinition(name: "mail_list_recent_messages", description: "List recent mail messages", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "calendar_upcoming_events", description: "List upcoming calendar events", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "rss_list_items", description: "List RSS item summaries", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(
        query: "读取今日日历、近两日邮件和近48小时RSS",
        definitions: definitions
    )

    #expect(Set(matches.map(\.name)) == [
        "calendar_upcoming_events",
        "mail_list_recent_messages",
        "rss_list_items"
    ])
}

@Test func toolSearchDiscoversNonWebFamiliesUsingChineseCapabilityNames() {
    let definitions = [
        AgentToolDefinition(name: "science_compute", description: "Evaluate an expression", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "image_search", description: "Find images", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "connor_skill_list", description: "List installed skills", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "get_current_environment", description: "Read environment context", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(
        query: "科学计算、图片、技能、天气和工作区文件",
        definitions: definitions,
        maximumResults: 8
    )

    #expect(Set(result.tools.map(\.name)) == Set(definitions.map(\.name)))
    #expect(Set(result.matchedNamespaces) == ["environment", "image", "science", "skill", "workspace"])
}

@Test func toolCatalogIncludesNamespacePurposeInsteadOfCountsAlone() {
    let definitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]

    let catalog = AssistantToolRouter().compactCatalogSummary(definitions: definitions)

    #expect(catalog.contains("mail accounts, recent messages"))
    #expect(catalog.contains("邮件、邮箱与收件箱"))
}

@Test func finalAttentionRSSSearchRemainsPubliclyDiscoverable() {
    let definitions = [
        AgentToolDefinition(name: "attention_brief", description: "Internal attention aggregation", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "rss_search_items", description: "Search RSS items", inputSchema: .object(properties: [:], required: []))
    ]

    let route = AssistantToolRouter().route(definitions: definitions)
    let matches = AssistantToolRouter().discover(query: "近48小时RSS", definitions: definitions)

    #expect(!route.discoverableDefinitions.contains { $0.name == "attention_brief" })
    #expect(route.discoverableDefinitions.contains { $0.name == "rss_search_items" })
    #expect(matches.map(\.name) == ["rss_search_items"])
}

@Test func toolDiscoveryReportsRecoverableNamespaceMetadataForNoMatch() {
    let definitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "calendar_search_events", description: "Search calendar events", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(query: "量子纠缠实验", definitions: definitions)

    #expect(result.tools.isEmpty)
    #expect(result.requestedNamespaces.isEmpty)
    #expect(result.matchedNamespaces.isEmpty)
    #expect(result.availableNamespaces == ["calendar", "mail"])
}

@Test func toolDiscoveryReportsRequestedButUnavailableNamespace() {
    let definitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(query: "读取本地工作区文件", definitions: definitions)

    #expect(result.tools.isEmpty)
    #expect(result.requestedNamespaces == ["workspace"])
    #expect(result.matchedNamespaces.isEmpty)
    #expect(result.unavailableNamespaces == ["workspace"])
    #expect(result.availableNamespaces == ["mail"])
}

@Test func toolDiscoveryDoesNotReportNamespacesOutsideTheExposedDefinitions() {
    let exposedDefinitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(
        query: "读取日历和邮件",
        definitions: exposedDefinitions
    )

    #expect(result.matchedNamespaces == ["mail"])
    #expect(result.availableNamespaces == ["mail"])
    #expect(result.tools.map(\.name) == ["mail_search_messages"])
}

@Test func sessionSearchIsDiscoveredUnderMemoryNamespace() {
    let definitions = [
        AgentToolDefinition(name: "session_search", description: "raw chat transcript search", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "session_list_by_status", description: "session status listing", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "memory_os_recent_context", description: "memory recent context", inputSchema: .object(properties: [:], required: []))
    ]

    let discovered = AssistantToolRouter().discover(query: "记忆", definitions: definitions)

    #expect(discovered.contains { $0.name == "session_search" })
    #expect(discovered.contains { $0.name == "memory_os_recent_context" })
    #expect(!discovered.contains { $0.name == "session_list_by_status" })
}

@Test func taskToolsAreDiscoverableUnderTaskNamespace() {
    let definitions = [
        AgentToolDefinition(name: "tasks_list", description: "List Connor task definitions", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "tasks_create_scheduled_session_message", description: "Create an AI task that creates a new session at a specific time or on a schedule, then sends a message", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "tasks_delete", description: "Delete a task", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "calendar_search_events", description: "Search calendar events", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(
        query: "创建定时任务 scheduled task 提醒",
        definitions: definitions
    )

    #expect(result.matchedNamespaces.contains("task"))
    #expect(!result.unavailableNamespaces.contains("task"))
    #expect(result.availableNamespaces.contains("task"))
    #expect(result.tools.contains { $0.name == "tasks_create_scheduled_session_message" })
    #expect(result.tools.contains { $0.name == "tasks_list" })
}

@Test func toolSearchRecallsSemanticSynonymsWithoutExactWords() {
    let definitions = [
        AgentToolDefinition(name: "science_compute", description: "Evaluate an expression", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "note_search", description: "Search notes", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "please calculate this", definitions: definitions)

    #expect(matches.map(\.name) == ["science_compute"])
}

@Test func toolSearchMatchesChineseParaphraseOfCapabilities() {
    let definitions = [
        AgentToolDefinition(name: "rss_list_items", description: "List RSS item summaries", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "rss_search_items", description: "Search RSS items", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "note_search", description: "Search notes", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "帮我看看最近的新闻", definitions: definitions)

    #expect(matches.first?.name == "rss_search_items")
    #expect(!matches.contains { $0.name == "note_search" })
}

@Test func toolSearchToleratesEnglishTyposViaFuzzyMatching() {
    let definitions = [
        AgentToolDefinition(name: "calendar_search_events", description: "Search calendar events", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "calender events", definitions: definitions)

    #expect(matches.first?.name == "calendar_search_events")
}

@Test func toolSearchRanksReadToolsForFileReadingIntent() {
    let definitions = [
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Glob", description: "List files matching a pattern", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "ApplyPatch", description: "Edit workspace files", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "读取本地文件", definitions: definitions)

    #expect(matches.first?.name == "Read")
}

@Test func toolSearchExpandsDomainSynonymsForRecall() {
    let definitions = [
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "rss_search_items", description: "Search RSS items", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "calendar_search_events", description: "Search calendar events", inputSchema: .object(properties: [:], required: []))
    ]

    let mail = AssistantToolRouter().discover(query: "gmail 收件箱", definitions: definitions)
    let news = AssistantToolRouter().discover(query: "news", definitions: definitions)

    #expect(mail.map(\.name) == ["mail_search_messages"])
    #expect(news.map(\.name) == ["rss_search_items"])
}

@Test func toolSearchFindsToolsByMixedLanguageSemanticSignals() {
    let definitions = [
        AgentToolDefinition(name: "web_fetch", description: "Fetch a web page", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "browser_navigate", description: "Navigate a browser page", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "note_search", description: "Search notes", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "打开网页 online", definitions: definitions)

    #expect(Set(matches.map(\.name)) == ["web_fetch", "browser_navigate"])
}

@Test func toolSearchKeepsPrecisionForGenericSearchQueries() {
    let definitions = [
        AgentToolDefinition(name: "note_search", description: "Search notes", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "calendar_upcoming_events", description: "Upcoming calendar events", inputSchema: .object(properties: [:], required: []))
    ]

    let matches = AssistantToolRouter().discover(query: "search", definitions: definitions, maximumResults: 2)

    #expect(Set(matches.map(\.name)) == ["note_search", "mail_search_messages"])
    #expect(!matches.contains { $0.name == "calendar_upcoming_events" })
}

@Test func toolSearchRecoversDirectWorkspaceToolsThroughRuntimeCatalogWiring() {
    let definitions = [
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Glob", description: "List files matching a pattern", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Shell", description: "Execute a shell command in the workspace", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "ApplyPatch", description: "Apply an ordered set of structured file changes inside the workspace", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]
    let router = AssistantToolRouter()
    let route = router.route(definitions: definitions)
    #expect(!route.discoverableDefinitions.contains { $0.name == "ApplyPatch" })

    // 修复 A 之前的运行时行为：只把过滤后的 discoverableDefinitions 喂给 discovery，
    // 直接工具永远进不了候选列表，写入类查询也搜不到 ApplyPatch。
    let beforeFix = router.discovery(
        query: "工作区 写入 保存 补丁 patch",
        definitions: route.discoverableDefinitions
    )
    #expect(!beforeFix.tools.contains { $0.name == "ApplyPatch" })

    // 修复 A 之后：运行时传入完整注册目录，discovery 内部重新加回直接工具。
    let afterFix = router.discovery(
        query: "工作区 写入 保存 补丁 patch",
        definitions: definitions
    )
    #expect(afterFix.tools.first?.name == "ApplyPatch")
    let neutral = router.discovery(query: "本地工作区文件工具", definitions: definitions)
    #expect(Set(neutral.tools.map(\.name)).isSuperset(of: ["Shell", "ApplyPatch"]))
}

@Test func toolSearchFindsApplyPatchForWorkspaceWritePhrases() {
    let definitions = [
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Glob", description: "List files matching a pattern", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Shell", description: "Inspect and search workspace files", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "ApplyPatch", description: "Edit workspace files", inputSchema: .object(properties: [:], required: []))
    ]
    for query in ["写文件", "写入文件", "创建文件", "新建文件", "新增文件", "保存文件", "改文件", "修改文件", "编辑文件", "打补丁", "删除文件", "文件操作"] {
        let matches = AssistantToolRouter().discover(query: query, definitions: definitions)
        #expect(matches.first?.name == "ApplyPatch", "写入类查询应优先命中 ApplyPatch: \(query)")
    }
}

@Test func toolSearchFindsShellForRunAndGitQueries() {
    let definitions = [
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Glob", description: "List files matching a pattern", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Shell", description: "Execute a shell command in the workspace: inspect files, query Git, run builds, tests, and scripts", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "ApplyPatch", description: "Edit workspace files", inputSchema: .object(properties: [:], required: []))
    ]
    for query in ["执行命令", "执行 git 命令", "运行终端命令", "用 shell 跑命令", "命令行工具", "构建项目", "跑测试", "运行项目测试", "查询 git 状态", "执行构建和测试"] {
        let matches = AssistantToolRouter().discover(query: query, definitions: definitions)
        #expect(matches.first?.name == "Shell", "操作类查询应优先命中 Shell: \(query)")
    }
}

@Test func toolSearchDiscoversMCPAndLoadContentTools() {
    let definitions = [
        AgentToolDefinition(name: "mcp__github__get_repo", description: "Fetch repository details from the GitHub connector", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "load_attachment_context", description: "Load selected historical session attachments into this run", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Read", description: "Read a workspace file", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email inbox", inputSchema: .object(properties: [:], required: []))
    ]
    let mcpMatches = AssistantToolRouter().discover(query: "mcp 外部工具 数据源", definitions: definitions)
    #expect(mcpMatches.first?.name.hasPrefix("mcp__") == true)
    for query in ["加载附件", "读取内容", "load attachment context"] {
        let matches = AssistantToolRouter().discover(query: query, definitions: definitions)
        #expect(matches.first?.name == "load_attachment_context", "内容加载查询应命中 load_attachment_context: \(query)")
    }
}

@Test func toolSearchDiscoversBaseFamilyUsingChineseCapabilityNames() {
    let definitions = [
        AgentToolDefinition(name: "base_record_mutate", description: "Write records via the single mutate entry", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "base_query_aggregate", description: "Aggregate records deterministically", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "base_app_create", description: "Create a small app with its four artifacts", inputSchema: .object(properties: [:], required: []))
    ]

    let result = AssistantToolRouter().discovery(
        query: "记一笔账，按月看预算",
        definitions: definitions,
        maximumResults: 8
    )

    #expect(Set(result.tools.map(\.name)) == Set(definitions.map(\.name)))
    #expect(result.matchedNamespaces == ["base"])
    #expect(result.availableNamespaces.contains("base"))
}
