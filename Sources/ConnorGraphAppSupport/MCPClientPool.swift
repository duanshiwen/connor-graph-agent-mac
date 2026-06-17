import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum MCPClientPoolError: Error, Sendable, Equatable, CustomStringConvertible {
    case sourceNotFound(String)
    case sourceNotEnabled(String)
    case unsupportedTransport(String)
    case unsupportedCredentialRequirement(ProductOSCredentialRequirement)
    case toolNotInPersistedCatalog(String)

    public var description: String {
        switch self {
        case .sourceNotFound(let sourceID): "sourceNotFound: \(sourceID)"
        case .sourceNotEnabled(let sourceID): "sourceNotEnabled: \(sourceID)"
        case .unsupportedTransport(let message): "unsupportedTransport: \(message)"
        case .unsupportedCredentialRequirement(let requirement): "unsupportedCredentialRequirement: \(requirement.rawValue)"
        case .toolNotInPersistedCatalog(let toolName): "toolNotInPersistedCatalog: \(toolName)"
        }
    }
}

/// Commercial MCP runtime pool entry point.
///
/// Current MVP scope:
/// - Loads Connor-owned source configurations from `AppMCPSourceRuntimeRepository`.
/// - Exposes persisted catalogs for enabled sources to the Agent runtime.
/// - Routes Agent tool calls to real stdio MCP servers.
/// - Persists invocation audit records after every call.
///
/// Pending later phases: long-lived connection reuse, HTTP/SSE transports, Keychain-backed
/// credential injection, activation hot reload, and result artifact governance.
public actor MCPClientPool: MCPToolRouting {
    public var repository: AppMCPSourceRuntimeRepository
    public var clientName: String
    public var clientVersion: String
    public var currentDirectoryURL: URL?

    private var stdioRuntimes: [String: MCPSourceRuntime<MCPStdioClientTransport>] = [:]

    public init(
        repository: AppMCPSourceRuntimeRepository,
        clientName: String = "Connor",
        clientVersion: String = "1.0",
        currentDirectoryURL: URL? = nil
    ) {
        self.repository = repository
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.currentDirectoryURL = currentDirectoryURL
    }

    public nonisolated static func loadEnabledPersistedCatalog(repository: AppMCPSourceRuntimeRepository) throws -> [MCPSourceToolDescriptor] {
        let configurations = try repository.list().filter { $0.status == .enabled }
        var catalog: [MCPSourceToolDescriptor] = []
        for configuration in configurations {
            let descriptors = try repository.loadToolCatalog(sourceID: configuration.sourceID)
            catalog.append(contentsOf: descriptors.map { descriptor in
                let exposedName = descriptor.name.hasPrefix("mcp__")
                    ? descriptor.name
                    : MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: descriptor.sourceID, rawToolName: descriptor.rawName)
                return MCPSourceToolDescriptor(
                    sourceID: descriptor.sourceID,
                    name: exposedName,
                    rawName: descriptor.rawName,
                    description: descriptor.description,
                    inputSchema: descriptor.inputSchema,
                    requiredCapabilities: descriptor.requiredCapabilities
                )
            })
        }
        return catalog.sorted { $0.name < $1.name }
    }

    public func refreshEnabledStdioSources(now: Date = Date()) async throws -> [MCPSourceTestReport] {
        let service = MCPSourceTestService(
            repository: repository,
            clientName: clientName,
            clientVersion: clientVersion,
            currentDirectoryURL: currentDirectoryURL
        )
        var reports: [MCPSourceTestReport] = []
        for configuration in try repository.list().filter({ $0.status == .enabled }) {
            let report = try await service.testStdioSource(configuration, now: now)
            reports.append(report)
        }
        return reports
    }

    public func callMCPTool(
        exposedToolName: String,
        sourceID: String,
        rawToolName: String,
        arguments: MCPJSONValue,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult {
        let configuration = try sourceConfiguration(sourceID: sourceID)
        guard configuration.status == .enabled else { throw MCPClientPoolError.sourceNotEnabled(sourceID) }
        guard try persistedCatalogContains(sourceID: sourceID, exposedToolName: exposedToolName, rawToolName: rawToolName) else {
            throw MCPClientPoolError.toolNotInPersistedCatalog(exposedToolName)
        }
        let runtime = try runtime(for: configuration)
        let invocation = try await runtime.callTool(
            name: exposedToolName,
            arguments: arguments,
            runID: context.runID,
            sessionID: context.sessionID
        )
        try repository.appendAuditRecords(invocation.auditRecords)
        return invocation.result
    }

    public func closeAll() async {
        let runtimes = stdioRuntimes
        stdioRuntimes.removeAll()
        for runtime in runtimes.values {
            try? await runtime.shutdown()
        }
    }

    private func sourceConfiguration(sourceID: String) throws -> MCPSourceRuntimeConfiguration {
        guard let configuration = try repository.load(sourceID: sourceID) else {
            throw MCPClientPoolError.sourceNotFound(sourceID)
        }
        return configuration
    }

    private func runtime(for configuration: MCPSourceRuntimeConfiguration) throws -> MCPSourceRuntime<MCPStdioClientTransport> {
        if let runtime = stdioRuntimes[configuration.sourceID] { return runtime }
        guard configuration.credentialRequirement == .none else {
            throw MCPClientPoolError.unsupportedCredentialRequirement(configuration.credentialRequirement)
        }
        guard case .stdio(let command, let arguments) = configuration.transport else {
            throw MCPClientPoolError.unsupportedTransport("MVP pool currently supports stdio sources only.")
        }
        let transport = MCPStdioClientTransport(
            command: command,
            arguments: arguments,
            environment: [:],
            currentDirectoryURL: currentDirectoryURL
        )
        let client = MCPJSONRPCClient(transport: transport, clientName: clientName, clientVersion: clientVersion)
        let runtime = MCPSourceRuntime(configuration: configuration, client: client)
        stdioRuntimes[configuration.sourceID] = runtime
        return runtime
    }

    private func persistedCatalogContains(sourceID: String, exposedToolName: String, rawToolName: String) throws -> Bool {
        try repository.loadToolCatalog(sourceID: sourceID).contains { descriptor in
            descriptor.rawName == rawToolName && (
                descriptor.name == exposedToolName ||
                MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: descriptor.sourceID, rawToolName: descriptor.rawName) == exposedToolName
            )
        }
    }
}
