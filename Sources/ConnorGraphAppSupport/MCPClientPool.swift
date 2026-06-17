import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum MCPClientPoolError: Error, Sendable, Equatable, CustomStringConvertible {
    case sourceNotFound(String)
    case sourceNotEnabled(String)
    case unsupportedTransport(String)
    case unsupportedCredentialRequirement(ProductOSCredentialRequirement)
    case toolNotInPersistedCatalog(String)
    case toolPolicyBlocked(String)
    case toolDefinitionChanged(String)

    public var description: String {
        switch self {
        case .sourceNotFound(let sourceID): "sourceNotFound: \(sourceID)"
        case .sourceNotEnabled(let sourceID): "sourceNotEnabled: \(sourceID)"
        case .unsupportedTransport(let message): "unsupportedTransport: \(message)"
        case .unsupportedCredentialRequirement(let requirement): "unsupportedCredentialRequirement: \(requirement.rawValue)"
        case .toolNotInPersistedCatalog(let toolName): "toolNotInPersistedCatalog: \(toolName)"
        case .toolPolicyBlocked(let toolName): "toolPolicyBlocked: \(toolName)"
        case .toolDefinitionChanged(let toolName): "toolDefinitionChanged: \(toolName)"
        }
    }
}

/// Commercial MCP runtime pool entry point.
///
/// Responsibilities:
/// - Loads Connor-owned source configurations from `AppMCPSourceRuntimeRepository`.
/// - Exposes persisted catalogs for enabled sources to the Agent runtime.
/// - Enforces per-tool governance policy and definition integrity before execution.
/// - Routes governed Agent tool calls to real stdio MCP servers.
/// - Persists invocation and governance audit records after every call.
///
/// Remaining product expansion: long-lived connection reuse, HTTP/SSE transports, Keychain-backed
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
                    requiredCapabilities: descriptor.requiredCapabilities,
                    governancePolicy: descriptor.governancePolicy,
                    definitionFingerprint: descriptor.definitionFingerprint,
                    integrityStatus: descriptor.integrityStatus
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
        guard let descriptor = try persistedCatalogDescriptor(sourceID: sourceID, exposedToolName: exposedToolName, rawToolName: rawToolName) else {
            throw MCPClientPoolError.toolNotInPersistedCatalog(exposedToolName)
        }
        try await enforcePolicy(descriptor: descriptor, arguments: arguments, context: context)
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
            throw MCPClientPoolError.unsupportedTransport("Runtime pool currently supports stdio sources only; HTTP/SSE transport is not enabled yet.")
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

    private func persistedCatalogDescriptor(sourceID: String, exposedToolName: String, rawToolName: String) throws -> MCPSourceToolDescriptor? {
        try repository.loadToolCatalog(sourceID: sourceID).first { descriptor in
            descriptor.rawName == rawToolName && (
                descriptor.name == exposedToolName ||
                MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: descriptor.sourceID, rawToolName: descriptor.rawName) == exposedToolName
            )
        }
    }

    private func enforcePolicy(
        descriptor: MCPSourceToolDescriptor,
        arguments: MCPJSONValue,
        context: AgentToolExecutionContext
    ) async throws {
        let policy = descriptor.governancePolicy ?? MCPToolGovernancePolicy(
            riskClass: .unknown,
            executionPolicy: .requireConfirmation,
            permissionCapability: .runNetworkShellCommand,
            rationale: "Missing persisted MCP tool governance policy; fail-safe confirmation required."
        )
        let payloadJSON = (try? jsonString(arguments)) ?? "{}"
        if descriptor.integrityStatus == .changed {
            try repository.appendAuditRecord(MCPSourceRuntimeAuditRecord(
                sourceID: descriptor.sourceID,
                runID: context.runID,
                sessionID: context.sessionID,
                eventKind: .toolDefinitionChanged,
                rawToolName: descriptor.rawName,
                prefixedToolName: descriptor.name,
                permissionCapability: policy.permissionCapability,
                requiredCapabilities: descriptor.requiredCapabilities,
                riskClass: policy.riskClass,
                executionPolicy: policy.executionPolicy,
                integrityStatus: descriptor.integrityStatus,
                errorSummary: "Execution blocked because the persisted tool definition hash changed. Re-test and review this source before use."
            ))
            throw MCPClientPoolError.toolDefinitionChanged(descriptor.name)
        }
        if policy.executionPolicy == .block {
            try repository.appendAuditRecord(MCPSourceRuntimeAuditRecord(
                sourceID: descriptor.sourceID,
                runID: context.runID,
                sessionID: context.sessionID,
                eventKind: .toolPolicyBlocked,
                rawToolName: descriptor.rawName,
                prefixedToolName: descriptor.name,
                permissionCapability: policy.permissionCapability,
                requiredCapabilities: descriptor.requiredCapabilities,
                riskClass: policy.riskClass,
                executionPolicy: policy.executionPolicy,
                integrityStatus: descriptor.integrityStatus,
                errorSummary: policy.rationale
            ))
            throw MCPClientPoolError.toolPolicyBlocked(descriptor.name)
        }
        if policy.executionPolicy == .requireConfirmation && !context.approvedCapabilities.contains(policy.permissionCapability) {
            let decision = await context.policyEngine.evaluate(
                capability: policy.permissionCapability,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: descriptor.name,
                payloadJSON: payloadJSON
            )
            switch decision.outcome {
            case .approved:
                // Commercial MCP governance requires explicit, per-run approval for sensitive MCP tools.
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: decision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: policy.permissionCapability,
                    toolName: descriptor.name,
                    payloadJSON: payloadJSON
                ))
            case .needsApproval:
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: decision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: policy.permissionCapability,
                    toolName: descriptor.name,
                    payloadJSON: payloadJSON
                ))
            case .denied:
                throw AgentToolError.permissionDenied(decision.reason)
            }
        }
    }

    private func jsonString(_ value: MCPJSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
