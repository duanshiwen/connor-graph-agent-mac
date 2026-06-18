import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporaryPhaseCStoragePaths(_ name: String = UUID().uuidString) -> AppStoragePaths {
    AppStoragePaths(applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ConnorPhaseCMCPSourceRuntime-\(name)", isDirectory: true))
}

@Test func mcpSourceRuntimeRepositoryPersistsSourceConfigurations() throws {
    let storagePaths = temporaryPhaseCStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "linear",
        displayName: "Linear",
        transport: .stdio(command: "npx", arguments: ["-y", "@modelcontextprotocol/server-linear"]),
        status: .enabled,
        credentialRequirement: .bearerToken,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "linear",
        graphIngestionEnabled: false,
        graphWritePolicy: .askToWrite
    )

    try repository.save(config)
    let loaded = try #require(try repository.load(sourceID: "linear"))

    #expect(loaded.sourceID == "linear")
    #expect(loaded.displayName == "Linear")
    #expect(loaded.transport == .stdio(command: "npx", arguments: ["-y", "@modelcontextprotocol/server-linear"]))
    #expect(loaded.status == .enabled)
    #expect(loaded.toolNamePrefix == "linear")
    #expect(loaded.allowedCapabilities == [.externalNetwork, .readSession])
}

@Test func mcpSourceRuntimeRepositoryRejectsUnsafeSourcePolicies() throws {
    let storagePaths = temporaryPhaseCStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let unsafe = MCPSourceRuntimeConfiguration(
        sourceID: "unsafe-source",
        displayName: "Unsafe Source",
        transport: .http(url: URL(string: "https://example.com/mcp")!),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "unsafe",
        graphIngestionEnabled: true,
        graphWritePolicy: .allowAll
    )

    do {
        try repository.save(unsafe)
        Issue.record("Expected MCP source runtime repository to reject allowAll graph write policy")
    } catch let error as AppMCPSourceRuntimeRepositoryError {
        #expect(error == .unsafePermissionMode("MCP source unsafe-source cannot use allowAll graph write policy"))
    } catch {
        Issue.record("Expected AppMCPSourceRuntimeRepositoryError, got \(error)")
    }
}

@Test func mcpJSONRPCClientInitializesListsToolsCallsToolAndShutsDown() async throws {
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), result: .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("mock-mcp"), "version": .string("1.0.0")])
        ])),
        MCPJSONRPCMessage(id: .number(2), result: .object([
            "tools": .array([
                .object([
                    "name": .string("search"),
                    "description": .string("Search external system"),
                    "inputSchema": .object(["type": .string("object")])
                ])
            ])
        ])),
        MCPJSONRPCMessage(id: .number(3), result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string("found")])]),
            "isError": .bool(false)
        ]))
    ])
    let client = MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0")

    let initialization = try await client.initialize()
    let tools = try await client.listTools()
    let result = try await client.callTool(name: "search", arguments: .object(["query": .string("Connor")]))
    try await client.shutdown()

    #expect(initialization.protocolVersion == "2025-06-18")
    #expect(initialization.serverInfo.name == "mock-mcp")
    #expect(tools.map(\.name) == ["search"])
    #expect(result.content.first?.text == "found")
    let sentMethods = await transport.sent.compactMap(\.method)
    #expect(sentMethods == ["initialize", "notifications/initialized", "tools/list", "tools/call"])
    #expect(await transport.didClose)
}

@Test func mcpJSONRPCClientRejectsServerErrors() async throws {
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), error: MCPJSONRPCError(code: -32601, message: "Method not found"))
    ])
    let client = MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0")

    do {
        _ = try await client.initialize()
        Issue.record("Expected initialize to fail on JSON-RPC error")
    } catch let error as MCPJSONRPCClientError {
        #expect(error == .serverError(code: -32601, message: "Method not found"))
    } catch {
        Issue.record("Expected MCPJSONRPCClientError, got \(error)")
    }
}

@Test func mcpSourceRuntimeBuildsPrefixedToolCatalog() async throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "linear",
        displayName: "Linear",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "linear"
    )
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), result: .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("linear-mcp"), "version": .string("1")])
        ])),
        MCPJSONRPCMessage(id: .number(2), result: .object([
            "tools": .array([.object([
                "name": .string("list_issues"),
                "description": .string("List issues"),
                "inputSchema": .object(["type": .string("object")])
            ])])
        ]))
    ])
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    let catalog = try await runtime.discoverToolCatalog()

    #expect(catalog.map(\.name) == ["mcp__linear__list_issues"])
    #expect(catalog.first?.sourceID == "linear")
    #expect(catalog.first?.rawName == "list_issues")
    #expect(catalog.first?.requiredCapabilities == [.externalNetwork, .readSession])
}

@Test func mcpSourceRuntimeRejectsDisabledSourceBeforeCallingTransport() async throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "draft-source",
        displayName: "Draft Source",
        transport: .stdio(command: "mock", arguments: []),
        status: .disabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "draft"
    )
    let transport = MockMCPClientTransport()
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    do {
        _ = try await runtime.callTool(name: "draft.search", arguments: .object([:]), runID: "run-1", sessionID: "session-1")
        Issue.record("Expected disabled MCP source to reject tool call")
    } catch let error as MCPSourceRuntimeError {
        #expect(error == .sourceNotEnabled("draft-source"))
    } catch {
        Issue.record("Expected MCPSourceRuntimeError, got \(error)")
    }
    #expect(await transport.sent.isEmpty)
}

@Test func mcpSourceRuntimeCallsToolAndReturnsConnorEvents() async throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .oauth,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "github"
    )
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string("issue #1")])]),
            "isError": .bool(false)
        ]))
    ])
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    let invocation = try await runtime.callTool(name: "github.search_issues", arguments: .object(["q": .string("bug")]), runID: "run-1", sessionID: "session-1")

    #expect(invocation.sourceID == "github")
    #expect(invocation.rawToolName == "search_issues")
    #expect(invocation.result.contentText == "issue #1")
    #expect(invocation.events.map(\.kind) == [.permissionRequested, .toolStarted, .toolFinished])
    #expect(invocation.permissionRequest.capability == .externalNetwork)
    let sent = await transport.sent
    #expect(sent.first?.method == "tools/call")
    #expect(sent.first?.params?.objectValue?["name"] == .string("search_issues"))
}

@Test func mcpSourceRuntimeRepositorySyncsProductOSRegistryAndReturnsEvent() throws {
    let storagePaths = temporaryPhaseCStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let registryRepository = AppProductOSRegistryRepository(storagePaths: storagePaths)
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "notion",
        displayName: "Notion",
        transport: .http(url: URL(string: "https://notion.example/mcp")!),
        status: .enabled,
        credentialRequirement: .oauth,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "notion",
        graphIngestionEnabled: true,
        graphWritePolicy: .askToWrite
    )

    try repository.save(config)
    let result = try repository.syncProductOSRegistry(using: registryRepository, sessionID: "session-1", runID: "run-1")
    let notion = try #require(result.snapshot.sources.first { $0.id == "notion" })

    #expect(notion.kind == .mcp)
    #expect(notion.status == .enabled)
    #expect(result.event.kind == .sourceRegistryChanged)
    #expect(result.registryEvent.entryID == "notion")
    #expect(result.registryEvent.status == .enabled)
    #expect(result.registryEvent.sessionID == "session-1")
}

@Test func mcpSourceRuntimeRepositoryProducesProductOSSourceDefinition() throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .http(url: URL(string: "https://api.githubcopilot.com/mcp")!),
        status: .needsReview,
        credentialRequirement: .oauth,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "github",
        graphIngestionEnabled: true,
        graphWritePolicy: .askToWrite,
        tags: ["mcp", "code"]
    )

    let source = config.productOSSourceDefinition()

    #expect(source.id == "github")
    #expect(source.kind == .mcp)
    #expect(source.status == .needsReview)
    #expect(source.endpoint == "https://api.githubcopilot.com/mcp")
    #expect(source.credentialRequirement == .oauth)
    #expect(source.allowedCapabilities == [.externalNetwork, .readSession])
    #expect(source.graphIngestionEnabled)
    #expect(source.graphWritePolicy == .askToWrite)
    #expect(source.tags.contains("mcp"))
}
