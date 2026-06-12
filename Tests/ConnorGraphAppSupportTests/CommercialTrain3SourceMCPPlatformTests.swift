import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporaryTrain3StoragePaths(_ name: String = UUID().uuidString) -> AppStoragePaths {
    AppStoragePaths(applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ConnorCommercialTrain3SourceMCP-\(name)", isDirectory: true))
}

@Test func commercialTrain3SourceRepositoryPersistsHealthCatalogAndAudit() throws {
    let storagePaths = temporaryTrain3StoragePaths()
    defer { try? FileManager.default.removeItem(at: storagePaths.applicationSupportDirectory) }
    let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
    let source = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "github",
        graphIngestionEnabled: true,
        graphWritePolicy: .askToWrite
    )
    let capability = MCPSourceRuntimeCapabilitySnapshot(
        protocolVersion: "2025-11-25",
        serverName: "github-mcp",
        serverVersion: "1.0.0",
        supportsTools: true,
        supportsResources: true,
        toolCount: 1,
        toolNames: ["search_issues"]
    )
    let health = MCPSourceRuntimeHealthRecord(
        sourceID: "github",
        healthStatus: .healthy,
        lifecycleState: .enabled,
        capabilitySnapshot: capability,
        discoveredToolCount: 1,
        auditedInvocationCount: 1
    )
    let catalog = [MCPSourceToolDescriptor(
        sourceID: "github",
        name: "github.search_issues",
        rawName: "search_issues",
        description: "Search issues",
        inputSchema: .object(["type": .string("object")]),
        requiredCapabilities: [.externalNetwork, .readSession]
    )]
    let audit = MCPSourceRuntimeAuditRecord(
        sourceID: "github",
        runID: "run-1",
        sessionID: "session-1",
        eventKind: .toolFinished,
        rawToolName: "search_issues",
        prefixedToolName: "github.search_issues",
        requiredCapabilities: [.externalNetwork, .readSession],
        resultSummary: "issue #1"
    )

    try repository.save(source)
    try repository.saveHealthRecord(health)
    try repository.saveToolCatalog(sourceID: "github", catalog: catalog)
    try repository.appendAuditRecord(audit)

    let loadedHealth = try #require(try repository.loadHealthRecord(sourceID: "github"))
    let loadedCatalog = try repository.loadToolCatalog(sourceID: "github")
    let loadedAudit = try repository.loadRecentAuditRecords(sourceID: "github")

    #expect(loadedHealth.healthStatus == .healthy)
    #expect(loadedHealth.capabilitySnapshot?.supportsResources == true)
    #expect(loadedCatalog.map(\.name) == ["github.search_issues"])
    #expect(loadedAudit.map(\.eventKind) == [.toolFinished])
}

@Test func commercialTrain3RuntimeDiscoveryBuildsHealthCapabilityAndCatalogSnapshot() async throws {
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
            "protocolVersion": .string("2025-11-25"),
            "capabilities": .object([
                "tools": .object([:]),
                "resources": .object([:]),
                "prompts": .object([:]),
                "elicitation": .object([:])
            ]),
            "serverInfo": .object(["name": .string("linear-mcp"), "version": .string("2.0")])
        ])),
        MCPJSONRPCMessage(id: .number(2), result: .object([
            "tools": .array([
                .object([
                    "name": .string("list_issues"),
                    "description": .string("List issues"),
                    "inputSchema": .object(["type": .string("object")])
                ])
            ])
        ]))
    ])
    let runtime = MCPSourceRuntime(configuration: config, client: MCPJSONRPCClient(transport: transport, clientName: "Connor", clientVersion: "1.0"))

    let snapshot = try await runtime.discoverRuntimeState()

    #expect(snapshot.healthRecord.healthStatus == .healthy)
    #expect(snapshot.healthRecord.capabilitySnapshot?.protocolVersion == "2025-11-25")
    #expect(snapshot.healthRecord.capabilitySnapshot?.supportsElicitation == true)
    #expect(snapshot.catalog.map(\.name) == ["linear.list_issues"])
    #expect(snapshot.auditRecords.map(\.eventKind) == [.discoveryStarted, .discoveryFinished])
}

@Test func commercialTrain3ToolInvocationCarriesSourceAuditEnvelope() async throws {
    let config = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
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

    let invocation = try await runtime.callTool(
        name: "github.search_issues",
        arguments: .object(["q": .string("bug")]),
        runID: "run-1",
        sessionID: "session-1"
    )

    #expect(invocation.events.map(\.kind) == [.permissionRequested, .toolStarted, .toolFinished])
    #expect(invocation.auditRecords.map(\.eventKind) == [.toolPermissionRequested, .toolStarted, .toolFinished])
    #expect(invocation.auditRecords.last?.resultSummary == "issue #1")
    #expect(invocation.auditRecords.first?.permissionCapability == .externalNetwork)
}

@Test func commercialTrain3SourceUIPresentationShowsHealthCatalogAndAuditSignals() throws {
    let source = MCPSourceRuntimeConfiguration(
        sourceID: "notion",
        displayName: "Notion",
        transport: .http(url: URL(string: "https://notion.example/mcp")!),
        status: .enabled,
        credentialRequirement: .oauth,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "notion",
        graphIngestionEnabled: true,
        graphWritePolicy: .askToWrite,
        tags: ["docs"]
    )
    let health = MCPSourceRuntimeHealthRecord(
        sourceID: "notion",
        healthStatus: .healthy,
        lifecycleState: .enabled,
        capabilitySnapshot: MCPSourceRuntimeCapabilitySnapshot(
            protocolVersion: "2025-11-25",
            serverName: "notion-mcp",
            serverVersion: "1",
            supportsTools: true,
            supportsPrompts: true,
            toolCount: 2,
            toolNames: ["search", "get_page"]
        ),
        discoveredToolCount: 2,
        auditedInvocationCount: 3
    )
    let audit = MCPSourceRuntimeAuditRecord(sourceID: "notion", eventKind: .toolFinished)

    let presentation = SourceRuntimeUIPresentation.build(sources: [source], healthRecords: [health], auditRecords: [audit, audit, audit])
    let card = try #require(presentation.cards.first)

    #expect(presentation.summary.healthyCount == 1)
    #expect(presentation.summary.discoveredToolCount == 2)
    #expect(presentation.summary.auditedInvocationCount == 3)
    #expect(card.healthLabel == "healthy")
    #expect(card.toolCountLabel == "2 tools")
    #expect(card.platformCapabilityLabels.contains("prompts"))
    #expect(card.auditCountLabel == "3 audits")
}

@Test func commercialTrain3CommercialReadinessUsesHealthySourcePlatformEvidence() throws {
    let source = MCPSourceRuntimeConfiguration(
        sourceID: "github",
        displayName: "GitHub",
        transport: .stdio(command: "mock", arguments: []),
        status: .enabled,
        credentialRequirement: .none,
        allowedCapabilities: [.externalNetwork, .readSession],
        toolNamePrefix: "github",
        graphWritePolicy: .askToWrite
    )
    let health = MCPSourceRuntimeHealthRecord(
        sourceID: "github",
        healthStatus: .healthy,
        lifecycleState: .enabled,
        discoveredToolCount: 4
    )
    let audit = MCPSourceRuntimeAuditRecord(sourceID: "github", eventKind: .toolFinished)
    let input = CommercialReadinessInput(
        sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 1, labelDefinitionCount: 1, artifactDirectoriesReady: true),
        claudeSidecar: .ready(runtimeStatus: .ready, sdkSessionID: "sdk-1", healthStatus: "ready"),
        extensionRuntime: CommercialReadinessSnapshotBuilder().build(
            sessions: [AgentSession(id: "session-1", title: "Test")],
            governanceConfig: AppSessionGovernanceConfig.default,
            artifactDirectoriesReady: true,
            sidecarRecord: nil,
            sidecarHealthStatus: nil,
            sources: [source],
            sourceHealthRecords: [health],
            sourceAuditRecords: [audit],
            skills: [],
            automationConfig: ProductOSAutomationConfig(rules: []),
            graphMemoryDashboard: nil,
            shell: ConnorNativeShellPresentation.default,
            settingsPanelsReady: true
        ).extensionRuntime,
        graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0),
        nativeUI: .ready(shellItemCount: 1, commandCount: 1, settingsPanelsReady: true)
    )

    let dashboard = CommercialReadinessGate().evaluate(input)
    let card = try #require(dashboard.cards.first { $0.phase == .sourcesSkillsAutomations })

    #expect(card.status == .ready)
    #expect(card.metrics["healthySources"] == "1")
    #expect(card.metrics["discoveredTools"] == "4")
    #expect(card.metrics["sourceAudits"] == "1")
    #expect(card.metrics["governedSourcePolicy"] == "true")
}
