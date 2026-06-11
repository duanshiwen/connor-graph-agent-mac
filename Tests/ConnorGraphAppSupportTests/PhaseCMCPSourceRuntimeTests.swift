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
