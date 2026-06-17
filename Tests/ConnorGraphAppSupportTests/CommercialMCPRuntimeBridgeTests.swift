import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func appGraphAgentRuntimeFactoryRegistersPersistedEnabledMCPTools() async throws {
    let appDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorCommercialMCPRuntimeBridge-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appDirectory) }

    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()
    let fixture = try makeRuntimeBridgeMCPFixtureServer(in: appDirectory)

    let mcpRepository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "fixture",
        displayName: "Fixture MCP",
        transport: .stdio(command: "/usr/bin/python3", arguments: [fixture.path]),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork],
        toolNamePrefix: "fixture"
    )
    try mcpRepository.save(config)
    try mcpRepository.saveToolCatalog(sourceID: "fixture", catalog: [
        MCPSourceToolDescriptor(
            sourceID: "fixture",
            name: "mcp__fixture__echo",
            rawName: "echo",
            description: "Echo text through fixture MCP",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string"), "description": .string("Text to echo")])
                ]),
                "required": .array([.string("text")])
            ]),
            requiredCapabilities: [.externalNetwork]
        )
    ])

    let storeURL = appDirectory.appendingPathComponent("store.sqlite")
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalRuntimeBridgeSettingsStore(),
        credentialStore: LocalRuntimeBridgeCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)

    let controller = factory.makeAgentLoopController(permissionMode: AgentPermissionMode.readOnly)
    let definitions = controller.toolRegistry.definitions.map { $0.name }
    #expect(definitions.contains("mcp__fixture__echo"))

    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "mcp__fixture__echo", argumentsJSON: #"{"text":"hello runtime bridge"}"#),
        context: AgentToolExecutionContext(
            runID: "run-mcp-runtime-bridge",
            sessionID: "session-mcp-runtime-bridge",
            groupID: "default",
            userPrompt: "call fixture mcp",
            toolCallID: "tool-call-mcp-runtime-bridge",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentText == "hello runtime bridge")
    let audit = try mcpRepository.loadRecentAuditRecords(sourceID: "fixture", limit: 10)
    #expect(audit.map(\.eventKind).contains(.toolFinished))
}

private func makeRuntimeBridgeMCPFixtureServer(in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("runtime_bridge_fixture_mcp.py")
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
    if method == "tools/call":
        args = msg.get("params", {}).get("arguments", {})
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"content":[{"type":"text","text":args.get("text","")}],"isError":False}})
    elif method == "initialize":
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"runtime-bridge-fixture","version":"1"}}})
    elif method == "tools/list":
        send({"jsonrpc":"2.0","id":msg["id"],"result":{"tools":[{"name":"echo","description":"Echo text","inputSchema":{"type":"object"}}]}})
    else:
        send({"jsonrpc":"2.0","id":msg["id"],"error":{"code":-32601,"message":"Method not found"}})
"""#
    try script.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private struct LocalRuntimeBridgeSettingsStore: LLMSettingsStore {
    func string(forKey key: String) -> String? { nil }
    func set(_ value: String, forKey key: String) {}
}

private struct LocalRuntimeBridgeCredentialStore: CredentialStore {
    func saveSecret(_ secret: String, service: String, account: String) throws {}
    func readSecret(service: String, account: String) throws -> String? { nil }
    func deleteSecret(service: String, account: String) throws {}
}
