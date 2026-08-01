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
