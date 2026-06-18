import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum MCPSourceRuntimeTransport: Codable, Sendable, Equatable {
    case stdio(command: String, arguments: [String])
    case http(url: URL)

    private enum CodingKeys: String, CodingKey {
        case kind
        case command
        case arguments
        case url
    }

    private enum Kind: String, Codable {
        case stdio
        case http
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .stdio:
            self = .stdio(
                command: try container.decode(String.self, forKey: .command),
                arguments: try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
            )
        case .http:
            self = .http(url: try container.decode(URL.self, forKey: .url))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stdio(let command, let arguments):
            try container.encode(Kind.stdio, forKey: .kind)
            try container.encode(command, forKey: .command)
            try container.encode(arguments, forKey: .arguments)
        case .http(let url):
            try container.encode(Kind.http, forKey: .kind)
            try container.encode(url, forKey: .url)
        }
    }

    public var endpointDescription: String? {
        switch self {
        case .stdio(let command, let arguments):
            ([command] + arguments).joined(separator: " ")
        case .http(let url):
            url.absoluteString
        }
    }
}

public struct MCPSourceRuntimeConfiguration: Codable, Sendable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case sourceID
        case displayName
        case transport
        case status
        case credentialRequirement
        case credentialBindings
        case allowedCapabilities
        case toolNamePrefix
        case graphIngestionEnabled
        case graphWritePolicy
        case tags
        case notes
        case createdAt
        case updatedAt
    }

    public var id: String { sourceID }
    public var sourceID: String
    public var displayName: String
    public var transport: MCPSourceRuntimeTransport
    public var status: ProductOSRegistryEntryStatus
    public var credentialRequirement: ProductOSCredentialRequirement
    public var credentialBindings: [MCPSourceCredentialBinding]
    public var allowedCapabilities: [AgentPermissionCapability]
    public var toolNamePrefix: String
    public var graphIngestionEnabled: Bool
    public var graphWritePolicy: AgentPermissionMode
    public var tags: [String]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        sourceID: String,
        displayName: String,
        transport: MCPSourceRuntimeTransport,
        status: ProductOSRegistryEntryStatus = .draft,
        credentialRequirement: ProductOSCredentialRequirement = .none,
        credentialBindings: [MCPSourceCredentialBinding] = [],
        allowedCapabilities: [AgentPermissionCapability] = [.readSession],
        toolNamePrefix: String? = nil,
        graphIngestionEnabled: Bool = false,
        graphWritePolicy: AgentPermissionMode = .readOnly,
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.sourceID = sourceID
        self.displayName = displayName
        self.transport = transport
        self.status = status
        self.credentialRequirement = credentialRequirement
        self.credentialBindings = credentialBindings
        self.allowedCapabilities = allowedCapabilities
        self.toolNamePrefix = toolNamePrefix ?? sourceID
        self.graphIngestionEnabled = graphIngestionEnabled
        self.graphWritePolicy = graphWritePolicy
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        transport = try container.decode(MCPSourceRuntimeTransport.self, forKey: .transport)
        status = try container.decodeIfPresent(ProductOSRegistryEntryStatus.self, forKey: .status) ?? .draft
        credentialRequirement = try container.decodeIfPresent(ProductOSCredentialRequirement.self, forKey: .credentialRequirement) ?? .none
        credentialBindings = try container.decodeIfPresent([MCPSourceCredentialBinding].self, forKey: .credentialBindings) ?? []
        allowedCapabilities = try container.decodeIfPresent([AgentPermissionCapability].self, forKey: .allowedCapabilities) ?? [.readSession]
        toolNamePrefix = try container.decodeIfPresent(String.self, forKey: .toolNamePrefix) ?? sourceID
        graphIngestionEnabled = try container.decodeIfPresent(Bool.self, forKey: .graphIngestionEnabled) ?? false
        graphWritePolicy = try container.decodeIfPresent(AgentPermissionMode.self, forKey: .graphWritePolicy) ?? .readOnly
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func productOSSourceDefinition() -> ProductOSSourceDefinition {
        ProductOSSourceDefinition(
            id: sourceID,
            displayName: displayName,
            kind: .mcp,
            status: status,
            endpoint: transport.endpointDescription,
            credentialRequirement: credentialRequirement,
            allowedCapabilities: allowedCapabilities,
            graphIngestionEnabled: graphIngestionEnabled,
            graphWritePolicy: graphWritePolicy,
            tags: Array(Set(tags + ["mcp"])).sorted(),
            notes: notes.isEmpty ? "MCP source runtime managed by Connor. Tools, credentials, permissions, audit, and graph ingestion stay governed by Connor." : notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum AppMCPSourceRuntimeRepositoryError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidID(String)
    case invalidToolNamePrefix(String)
    case missingCommand(String)
    case unsafePermissionMode(String)
    case invalidHTTPEndpoint(String)

    public var description: String {
        switch self {
        case .invalidID(let id): "invalidID: \(id)"
        case .invalidToolNamePrefix(let prefix): "invalidToolNamePrefix: \(prefix)"
        case .missingCommand(let sourceID): "missingCommand: \(sourceID)"
        case .unsafePermissionMode(let message): "unsafePermissionMode: \(message)"
        case .invalidHTTPEndpoint(let message): "invalidHTTPEndpoint: \(message)"
        }
    }
}

public struct MCPSourceRuntimeRegistrySyncResult: Sendable, Equatable {
    public var snapshot: ProductOSRegistrySnapshot
    public var registryEvent: AgentProductOSRegistryEvent
    public var event: AgentEvent

    public init(snapshot: ProductOSRegistrySnapshot, registryEvent: AgentProductOSRegistryEvent) {
        self.snapshot = snapshot
        self.registryEvent = registryEvent
        self.event = .sourceRegistryChanged(registryEvent)
    }
}

public struct AppMCPSourceRuntimeRepository: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public var runtimeDirectory: URL { storagePaths.sourcesDirectory }

    public func sourceDirectory(sourceID: String) -> URL {
        runtimeDirectory.appendingPathComponent(sourceID, isDirectory: true)
    }

    public func configurationURL(sourceID: String) -> URL {
        sourceDirectory(sourceID: sourceID).appendingPathComponent("mcp-runtime.json")
    }

    public func healthURL(sourceID: String) -> URL {
        sourceDirectory(sourceID: sourceID).appendingPathComponent("health.json")
    }

    public func catalogURL(sourceID: String) -> URL {
        sourceDirectory(sourceID: sourceID).appendingPathComponent("catalog.json")
    }

    public func auditURL(sourceID: String) -> URL {
        sourceDirectory(sourceID: sourceID).appendingPathComponent("audit.jsonl")
    }

    public func save(_ configuration: MCPSourceRuntimeConfiguration) throws {
        try validate(configuration)
        try storagePaths.ensureDirectoryHierarchy()
        try FileManager.default.createDirectory(at: sourceDirectory(sourceID: configuration.sourceID), withIntermediateDirectories: true)
        var normalized = configuration
        normalized.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: configurationURL(sourceID: normalized.sourceID), options: .atomic)
    }

    public func saveHealthRecord(_ record: MCPSourceRuntimeHealthRecord) throws {
        try validateID(record.sourceID)
        try storagePaths.ensureDirectoryHierarchy()
        try FileManager.default.createDirectory(at: sourceDirectory(sourceID: record.sourceID), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: healthURL(sourceID: record.sourceID), options: .atomic)
    }

    public func loadHealthRecord(sourceID: String) throws -> MCPSourceRuntimeHealthRecord? {
        let url = healthURL(sourceID: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPSourceRuntimeHealthRecord.self, from: try Data(contentsOf: url))
    }

    public func listHealthRecords() throws -> [MCPSourceRuntimeHealthRecord] {
        guard FileManager.default.fileExists(atPath: runtimeDirectory.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(at: runtimeDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try entries.compactMap { entry -> MCPSourceRuntimeHealthRecord? in
            let url = entry.appendingPathComponent("health.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try decoder.decode(MCPSourceRuntimeHealthRecord.self, from: try Data(contentsOf: url))
        }.sorted { $0.sourceID < $1.sourceID }
    }

    public func saveToolCatalog(sourceID: String, catalog: [MCPSourceToolDescriptor]) throws {
        try validateID(sourceID)
        try storagePaths.ensureDirectoryHierarchy()
        try FileManager.default.createDirectory(at: sourceDirectory(sourceID: sourceID), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: catalogURL(sourceID: sourceID), options: .atomic)
    }

    public func loadToolCatalog(sourceID: String) throws -> [MCPSourceToolDescriptor] {
        let url = catalogURL(sourceID: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([MCPSourceToolDescriptor].self, from: try Data(contentsOf: url))
    }

    public func appendAuditRecord(_ record: MCPSourceRuntimeAuditRecord) throws {
        try validateID(record.sourceID)
        try storagePaths.ensureDirectoryHierarchy()
        try FileManager.default.createDirectory(at: sourceDirectory(sourceID: record.sourceID), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let line = String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
        let url = auditURL(sourceID: record.sourceID)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func appendAuditRecords(_ records: [MCPSourceRuntimeAuditRecord]) throws {
        for record in records { try appendAuditRecord(record) }
    }

    public func loadRecentAuditRecords(sourceID: String, limit: Int = 50) throws -> [MCPSourceRuntimeAuditRecord] {
        let url = auditURL(sourceID: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try text.split(separator: "\n").map { line in
            try decoder.decode(MCPSourceRuntimeAuditRecord.self, from: Data(line.utf8))
        }
        return Array(records.suffix(max(0, limit)))
    }

    public func deleteSourceRuntime(sourceID: String) throws {
        try validateID(sourceID)
        let directory = sourceDirectory(sourceID: sourceID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func validateForEnablement(_ configuration: MCPSourceRuntimeConfiguration) throws {
        try validate(configuration)
    }

    public func load(sourceID: String) throws -> MCPSourceRuntimeConfiguration? {
        let url = configurationURL(sourceID: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(MCPSourceRuntimeConfiguration.self, from: try Data(contentsOf: url))
        try validate(configuration)
        return configuration
    }

    public func list() throws -> [MCPSourceRuntimeConfiguration] {
        guard FileManager.default.fileExists(atPath: runtimeDirectory.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(at: runtimeDirectory, includingPropertiesForKeys: nil)
        let configs = try entries.compactMap { entry -> MCPSourceRuntimeConfiguration? in
            let url = entry.appendingPathComponent("mcp-runtime.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let configuration = try decoder.decode(MCPSourceRuntimeConfiguration.self, from: try Data(contentsOf: url))
            try validate(configuration)
            return configuration
        }
        return configs.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func syncProductOSRegistry(
        using registryRepository: AppProductOSRegistryRepository,
        sessionID: String,
        runID: String? = nil
    ) throws -> MCPSourceRuntimeRegistrySyncResult {
        let configurations = try list()
        var snapshot = try registryRepository.loadOrCreateDefault()
        for configuration in configurations {
            let source = configuration.productOSSourceDefinition()
            if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
                snapshot.sources[index] = source
            } else {
                snapshot.sources.append(source)
            }
        }
        try registryRepository.save(snapshot)
        let reloaded = try registryRepository.loadOrCreateDefault()
        let latestConfiguration = configurations.sorted { $0.updatedAt > $1.updatedAt }.first
        let registryEvent = AgentProductOSRegistryEvent(
            runID: runID,
            sessionID: sessionID,
            registryKind: "source",
            entryID: latestConfiguration?.sourceID ?? "mcp-source-runtime",
            status: latestConfiguration?.status,
            message: "MCP source runtime synchronized with Product OS registry."
        )
        return MCPSourceRuntimeRegistrySyncResult(snapshot: reloaded, registryEvent: registryEvent)
    }

    public func validate(_ configuration: MCPSourceRuntimeConfiguration) throws {
        try validateID(configuration.sourceID)
        try validateToolNamePrefix(configuration.toolNamePrefix)
        if configuration.graphWritePolicy == .allowAll {
            throw AppMCPSourceRuntimeRepositoryError.unsafePermissionMode("MCP source \(configuration.sourceID) cannot use allowAll graph write policy")
        }
        for binding in configuration.credentialBindings {
            _ = try MCPSourceCredentialStore.normalizedEnvironmentVariable(binding.environmentVariable)
        }
        switch configuration.transport {
        case .stdio(let command, _):
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AppMCPSourceRuntimeRepositoryError.missingCommand(configuration.sourceID)
            }
        case .http(let url):
            do {
                try MCPHTTPClientTransport.validateEndpoint(url)
            } catch {
                throw AppMCPSourceRuntimeRepositoryError.invalidHTTPEndpoint(String(describing: error))
            }
        }
    }

    private func validateID(_ id: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw AppMCPSourceRuntimeRepositoryError.invalidID(id)
        }
    }

    private func validateToolNamePrefix(_ prefix: String) throws {
        let pattern = #"^[a-zA-Z][a-zA-Z0-9_-]{0,63}$"#
        guard prefix.range(of: pattern, options: .regularExpression) != nil else {
            throw AppMCPSourceRuntimeRepositoryError.invalidToolNamePrefix(prefix)
        }
    }
}
