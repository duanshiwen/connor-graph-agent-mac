import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporaryCommercialMCPStoragePaths(_ name: String = UUID().uuidString) -> AppStoragePaths {
    AppStoragePaths(applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ConnorCommercialMCPPlatform-\(name)", isDirectory: true))
}

@Test func commercialMCPRuntimeUsesModelSafeToolNames() async throws {
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
                "name": .string("list.issues"),
                "description": .string("List issues"),
                "inputSchema": .object(["type": .string("object")])
            ])])
        ]))
    ])
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    let catalog = try await runtime.discoverToolCatalog()

    #expect(catalog.map(\.name) == ["mcp__linear__list_issues"])
    #expect(catalog.first?.rawName == "list.issues")
}

@Test func commercialMCPRuntimeAcceptsNewToolNameForCalls() async throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "github"
    )
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string("issue #1")])]),
            "isError": .bool(false)
        ]))
    ])
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    let invocation = try await runtime.callTool(name: "mcp__github__search_issues", arguments: .object(["q": .string("bug")]), runID: "run-1", sessionID: "session-1")

    #expect(invocation.rawToolName == "search_issues")
    #expect(invocation.prefixedToolName == "mcp__github__search_issues")
    #expect(invocation.result.contentText == "issue #1")
    let sent = await transport.sent
    #expect(sent.first?.params?.objectValue?["name"] == .string("search_issues"))
}

@Test func commercialMCPRegistryBridgeRegistersDiscoveredTools() async throws {
    let catalog = [MCPSourceToolDescriptor(
        sourceID: "search",
        name: "mcp__search__query",
        rawName: "query",
        description: "Run a search",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "q": .object(["type": .string("string"), "description": .string("Query")])
            ]),
            "required": .array([.string("q")])
        ]),
        requiredCapabilities: [.externalNetwork]
    )]
    let transport = MockMCPClientTransport(responses: [
        MCPJSONRPCMessage(id: .number(1), result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
            "isError": .bool(false)
        ]))
    ])
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "search",
        displayName: "Search",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "search"
    )
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))
    let router = MCPConcreteRuntimeRouter(runtimes: ["search": runtime])
    var registry = AgentToolRegistry()

    MCPToolRegistryBridge().registerTools(catalog: catalog, into: &registry, router: router)

    let definition = try #require(registry.definition(named: "mcp__search__query"))
    #expect(definition.name == "mcp__search__query")
    #expect(registry.permission(named: "mcp__search__query") == .externalNetwork)
}

@Test func commercialMCPStdioTransportFiltersSensitiveEnvironment() throws {
    let filtered = MCPStdioClientTransport.filteredEnvironment(overrides: [
        "OPENAI_API_KEY": "source-specific-override",
        "SAFE_VALUE": "ok"
    ])

    #expect(filtered["SAFE_VALUE"] == "ok")
    #expect(filtered["OPENAI_API_KEY"] == "source-specific-override")
    #expect(filtered["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
}

@Test func commercialMCPStdioTransportTalksToFixtureServer() async throws {
    let fixture = try makeMCPFixtureServer()
    defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
    let transport = MCPStdioClientTransport(command: "/usr/bin/python3", arguments: [fixture.path])
    let client = MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0")

    let initialization = try await client.initialize()
    let tools = try await client.listTools()
    let result = try await client.callTool(name: "echo", arguments: .object(["text": .string("hello")]))
    try await client.shutdown()

    #expect(initialization.serverInfo.name == "fixture-mcp")
    #expect(tools.map(\.name) == ["echo"])
    #expect(result.content.first?.text == "hello")
}

@Test func commercialMCPSourceTestServicePersistsDiscoveryArtifacts() async throws {
    let fixture = try makeMCPFixtureServer()
    defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
    let storagePaths = temporaryCommercialMCPStoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let configuration = MCPSourceRuntimeConfiguration(
        sourceID: "fixture",
        displayName: "Fixture MCP",
        transport: .stdio(command: "/usr/bin/python3", arguments: [fixture.path]),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "fixture"
    )
    try repository.save(configuration)
    let service = MCPSourceTestService(repository: repository, clientName: "ConnorTests", clientVersion: "1.0")

    let report = try await service.testStdioSource(configuration)

    #expect(report.success)
    #expect(report.catalog.map(\.name) == ["mcp__fixture__echo"])
    #expect(report.catalog.first?.rawName == "echo")
    #expect(report.healthRecord.healthStatus == .healthy)
    #expect(try repository.loadHealthRecord(sourceID: "fixture")?.healthStatus == .healthy)
    #expect(try repository.loadToolCatalog(sourceID: "fixture").map(\.name) == ["mcp__fixture__echo"])
    #expect(try repository.loadRecentAuditRecords(sourceID: "fixture").map(\.eventKind).contains(.discoveryFinished))
}

private func makeMCPFixtureServer() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorMCPFixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fixture_mcp.py")
    let script = #"""
import json, sys

def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line == b"\r\n":
            break
        key, value = line.decode("utf-8").split(":", 1)
        headers[key.lower()] = value.strip()
    length = int(headers["content-length"])
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))

def send(message):
    payload = json.dumps(message).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("utf-8"))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()

while True:
    msg = read_message()
    if msg is None:
        break
    method = msg.get("method")
    if "id" not in msg:
        continue
    if method == "initialize":
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"fixture-mcp","version":"1"}}})
    elif method == "tools/list":
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"tools":[{"name":"echo","description":"Echo text","inputSchema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}]}})
    elif method == "tools/call":
        args = msg.get("params", {}).get("arguments", {})
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"content":[{"type":"text","text":args.get("text","")}],"isError":False}})
    else:
        send({"jsonrpc":"2.0","id":msg["id"],"error":{"code":-32601,"message":"Method not found"}})
"""#
    try script.write(to: url, atomically: true, encoding: .utf8)
    return url
}
