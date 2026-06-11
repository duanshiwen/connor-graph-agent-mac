import Foundation

public enum ProductOSRegistryEntryStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case draft
    case enabled
    case disabled
    case needsReview
    case deprecated
}

public enum ProductOSSourceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case localFilesystem
    case mcp
    case restAPI
    case database
    case browser
    case sidecar
}

public enum ProductOSCredentialRequirement: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case bearerToken
    case basic
    case apiKeyHeader
    case apiKeyQuery
    case oauth
    case multiHeader
}

public struct ProductOSSourceDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var kind: ProductOSSourceKind
    public var status: ProductOSRegistryEntryStatus
    public var endpoint: String?
    public var credentialRequirement: ProductOSCredentialRequirement
    public var allowedCapabilities: [AgentPermissionCapability]
    public var graphIngestionEnabled: Bool
    public var graphWritePolicy: AgentPermissionMode
    public var tags: [String]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        kind: ProductOSSourceKind,
        status: ProductOSRegistryEntryStatus = .draft,
        endpoint: String? = nil,
        credentialRequirement: ProductOSCredentialRequirement = .none,
        allowedCapabilities: [AgentPermissionCapability] = [.readSession],
        graphIngestionEnabled: Bool = false,
        graphWritePolicy: AgentPermissionMode = .readOnly,
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.status = status
        self.endpoint = endpoint
        self.credentialRequirement = credentialRequirement
        self.allowedCapabilities = allowedCapabilities
        self.graphIngestionEnabled = graphIngestionEnabled
        self.graphWritePolicy = graphWritePolicy
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ProductOSSkillScope: String, Codable, Sendable, Equatable, CaseIterable {
    case global
    case home
    case project
}

public enum ProductOSSkillTrigger: String, Codable, Sendable, Equatable, CaseIterable {
    case manual
    case sessionStart
    case beforeModelRequest
    case afterModelResponse
    case sourceEvent
    case graphMemoryReview
}

public struct ProductOSSkillDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var scope: ProductOSSkillScope
    public var status: ProductOSRegistryEntryStatus
    public var manifestPath: String?
    public var triggers: [ProductOSSkillTrigger]
    public var requiredCapabilities: [AgentPermissionCapability]
    public var graphContextPolicy: AgentPermissionMode
    public var tags: [String]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        scope: ProductOSSkillScope = .home,
        status: ProductOSRegistryEntryStatus = .draft,
        manifestPath: String? = nil,
        triggers: [ProductOSSkillTrigger] = [.manual],
        requiredCapabilities: [AgentPermissionCapability] = [.readSession],
        graphContextPolicy: AgentPermissionMode = .readOnly,
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.scope = scope
        self.status = status
        self.manifestPath = manifestPath
        self.triggers = triggers
        self.requiredCapabilities = requiredCapabilities
        self.graphContextPolicy = graphContextPolicy
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProductOSRegistrySnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sources: [ProductOSSourceDefinition]
    public var skills: [ProductOSSkillDefinition]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        sources: [ProductOSSourceDefinition] = ProductOSSourceDefinition.defaults,
        skills: [ProductOSSkillDefinition] = ProductOSSkillDefinition.defaults,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.sources = sources.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.skills = skills.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.updatedAt = updatedAt
    }

    public static let `default` = ProductOSRegistrySnapshot()
}

public extension ProductOSSourceDefinition {
    static let defaults: [ProductOSSourceDefinition] = [
        ProductOSSourceDefinition(
            id: "local-filesystem",
            displayName: "Local Filesystem",
            kind: .localFilesystem,
            status: .enabled,
            credentialRequirement: .none,
            allowedCapabilities: [.readSession],
            graphIngestionEnabled: false,
            graphWritePolicy: .readOnly,
            tags: ["built-in", "local"],
            notes: "Built-in local read surface. Graph writes must still pass Connor admission."
        ),
        ProductOSSourceDefinition(
            id: "mcp-registry-placeholder",
            displayName: "MCP Source Registry",
            kind: .mcp,
            status: .draft,
            credentialRequirement: .oauth,
            allowedCapabilities: [.externalNetwork, .readSession],
            graphIngestionEnabled: false,
            graphWritePolicy: .askToWrite,
            tags: ["phase-4", "mcp"],
            notes: "Placeholder for future MCP/OAuth source runtime; disabled until connector execution is governed."
        )
    ]
}

public extension ProductOSSkillDefinition {
    static let defaults: [ProductOSSkillDefinition] = [
        ProductOSSkillDefinition(
            id: "graph-memory-review",
            displayName: "Graph Memory Review",
            scope: .home,
            status: .enabled,
            triggers: [.manual, .graphMemoryReview],
            requiredCapabilities: [.readSession, .commitGraphWrite],
            graphContextPolicy: .askToWrite,
            tags: ["built-in", "graph-memory"],
            notes: "Built-in skill profile for reviewing proposed graph memory before commit."
        ),
        ProductOSSkillDefinition(
            id: "session-summary",
            displayName: "Session Summary",
            scope: .home,
            status: .enabled,
            triggers: [.manual, .afterModelResponse],
            requiredCapabilities: [.readSession],
            graphContextPolicy: .readOnly,
            tags: ["built-in", "session"],
            notes: "Built-in skill profile for compact session summarization."
        )
    ]
}
