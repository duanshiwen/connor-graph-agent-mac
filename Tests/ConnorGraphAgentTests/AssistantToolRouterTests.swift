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
