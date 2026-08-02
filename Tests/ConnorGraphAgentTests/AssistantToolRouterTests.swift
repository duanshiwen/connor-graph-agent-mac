import Testing
@testable import ConnorGraphAgent

@Test func toolRouterHidesBootstrapToolsAndKeepsSmallStableSurface() {
    let definitions = [
        AgentToolDefinition(name: "memory_os_recent_context", description: "memory", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "mail_search_messages", description: "Search email", inputSchema: .object(properties: [:], required: [])),
        AgentToolDefinition(name: "Shell", description: "Run shell", inputSchema: .object(properties: [:], required: []))
    ]

    let route = AssistantToolRouter().route(definitions: definitions)

    #expect(!route.discoverableDefinitions.contains { $0.name == "memory_os_recent_context" })
    #expect(route.modelVisibleDefinitions.contains { $0.name == "Shell" })
    #expect(route.modelVisibleDefinitions.contains { $0.name == AssistantDecisionToolContract.searchName })
    #expect(!route.modelVisibleDefinitions.contains { $0.name == "mail_search_messages" })
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
