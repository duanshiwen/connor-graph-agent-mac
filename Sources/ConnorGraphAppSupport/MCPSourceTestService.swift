import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct MCPSourceTestReport: Sendable, Equatable {
    public var sourceID: String
    public var success: Bool
    public var healthRecord: MCPSourceRuntimeHealthRecord
    public var catalog: [MCPSourceToolDescriptor]
    public var auditRecords: [MCPSourceRuntimeAuditRecord]

    public init(
        sourceID: String,
        success: Bool,
        healthRecord: MCPSourceRuntimeHealthRecord,
        catalog: [MCPSourceToolDescriptor],
        auditRecords: [MCPSourceRuntimeAuditRecord]
    ) {
        self.sourceID = sourceID
        self.success = success
        self.healthRecord = healthRecord
        self.catalog = catalog
        self.auditRecords = auditRecords
    }
}

public enum MCPSourceTestServiceError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedTransport(String)

    public var description: String {
        switch self {
        case .unsupportedTransport(let message): "unsupportedTransport: \(message)"
        }
    }
}

public struct MCPSourceTestService: Sendable {
    public var repository: AppMCPSourceRuntimeRepository
    public var clientName: String
    public var clientVersion: String
    public var currentDirectoryURL: URL?
    public var credentialStore: MCPSourceCredentialStore

    public init(
        repository: AppMCPSourceRuntimeRepository,
        clientName: String = "Connor",
        clientVersion: String = "1.0",
        currentDirectoryURL: URL? = nil,
        credentialStore: MCPSourceCredentialStore = MCPSourceCredentialStore()
    ) {
        self.repository = repository
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.currentDirectoryURL = currentDirectoryURL
        self.credentialStore = credentialStore
    }

    public func testSource(_ configuration: MCPSourceRuntimeConfiguration, now: Date = Date()) async throws -> MCPSourceTestReport {
        try repository.validateForEnablement(configuration)
        switch configuration.transport {
        case .stdio(let command, let arguments):
            let environment = try credentialStore.environmentOverrides(for: configuration)
            let transport = MCPStdioClientTransport(
                command: command,
                arguments: arguments,
                environment: environment,
                currentDirectoryURL: currentDirectoryURL
            )
            let client = MCPJSONRPCClient(transport: transport, clientName: clientName, clientVersion: clientVersion)
            let runtime = MCPSourceRuntime(configuration: configuration, client: client)
            return try await discoverAndPersist(runtime: runtime, configuration: configuration, now: now)
        case .http(let url):
            let headers = try credentialStore.httpHeaders(for: configuration)
            let transport = try MCPHTTPClientTransport(endpointURL: url, headers: headers)
            let client = MCPJSONRPCClient(transport: transport, clientName: clientName, clientVersion: clientVersion)
            let runtime = MCPSourceRuntime(configuration: configuration, client: client)
            return try await discoverAndPersist(runtime: runtime, configuration: configuration, now: now)
        }
    }

    public func testStdioSource(_ configuration: MCPSourceRuntimeConfiguration, now: Date = Date()) async throws -> MCPSourceTestReport {
        try await testSource(configuration, now: now)
    }

    private func discoverAndPersist<Transport: MCPClientTransport>(
        runtime: MCPSourceRuntime<Transport>,
        configuration: MCPSourceRuntimeConfiguration,
        now: Date
    ) async throws -> MCPSourceTestReport {
        let previousCatalog = try repository.loadToolCatalog(sourceID: configuration.sourceID)
        let snapshot = try await runtime.discoverRuntimeState(now: now, previousCatalog: previousCatalog)
        let integrityAuditRecords = snapshot.catalog.compactMap { descriptor -> MCPSourceRuntimeAuditRecord? in
            guard descriptor.integrityStatus == .changed else { return nil }
            return MCPSourceRuntimeAuditRecord(
                sourceID: configuration.sourceID,
                eventKind: .toolDefinitionChanged,
                rawToolName: descriptor.rawName,
                prefixedToolName: descriptor.name,
                requiredCapabilities: descriptor.requiredCapabilities,
                riskClass: descriptor.governancePolicy?.riskClass,
                executionPolicy: descriptor.governancePolicy?.executionPolicy,
                integrityStatus: descriptor.integrityStatus,
                timestamp: now,
                errorSummary: "Tool definition changed since last approved discovery. Review policy before trusting this tool."
            )
        }
        try repository.saveHealthRecord(snapshot.healthRecord)
        try repository.saveToolCatalog(sourceID: configuration.sourceID, catalog: snapshot.catalog)
        try repository.appendAuditRecords(snapshot.auditRecords + integrityAuditRecords)
        try await runtime.shutdown()
        return MCPSourceTestReport(
            sourceID: configuration.sourceID,
            success: snapshot.healthRecord.healthStatus == .healthy,
            healthRecord: snapshot.healthRecord,
            catalog: snapshot.catalog,
            auditRecords: snapshot.auditRecords + integrityAuditRecords
        )
    }
}

/// Minimal router for tests and early app integration where one concrete runtime is already available.
public actor MCPConcreteRuntimeRouter<Transport: MCPClientTransport>: MCPToolRouting {
    private var runtimes: [String: MCPSourceRuntime<Transport>]

    public init(runtimes: [String: MCPSourceRuntime<Transport>]) {
        self.runtimes = runtimes
    }

    public func callMCPTool(
        exposedToolName: String,
        sourceID: String,
        rawToolName: String,
        arguments: MCPJSONValue,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult {
        guard let runtime = runtimes[sourceID] else {
            throw MCPToolRegistryBridgeError.missingSource(sourceID)
        }
        let invocation = try await runtime.callTool(
            name: exposedToolName,
            arguments: arguments,
            runID: context.runID,
            sessionID: context.sessionID
        )
        return invocation.result
    }
}
