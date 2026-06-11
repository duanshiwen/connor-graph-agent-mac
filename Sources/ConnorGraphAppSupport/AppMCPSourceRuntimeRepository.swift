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
    public var id: String { sourceID }
    public var sourceID: String
    public var displayName: String
    public var transport: MCPSourceRuntimeTransport
    public var status: ProductOSRegistryEntryStatus
    public var credentialRequirement: ProductOSCredentialRequirement
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
        self.allowedCapabilities = allowedCapabilities
        self.toolNamePrefix = toolNamePrefix ?? sourceID
        self.graphIngestionEnabled = graphIngestionEnabled
        self.graphWritePolicy = graphWritePolicy
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

    public var description: String {
        switch self {
        case .invalidID(let id): "invalidID: \(id)"
        case .invalidToolNamePrefix(let prefix): "invalidToolNamePrefix: \(prefix)"
        case .missingCommand(let sourceID): "missingCommand: \(sourceID)"
        case .unsafePermissionMode(let message): "unsafePermissionMode: \(message)"
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
        switch configuration.transport {
        case .stdio(let command, _):
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AppMCPSourceRuntimeRepositoryError.missingCommand(configuration.sourceID)
            }
        case .http:
            break
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
