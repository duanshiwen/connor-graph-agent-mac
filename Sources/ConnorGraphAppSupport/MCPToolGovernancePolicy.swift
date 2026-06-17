import Foundation
import CryptoKit
import ConnorGraphAgent
import ConnorGraphCore

public enum MCPToolRiskClass: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case read
    case externalRead
    case mutation
    case destructive
    case admin
    case credentialAccess
    case unknown

    public var displayName: String {
        switch self {
        case .read: "Read"
        case .externalRead: "External Read"
        case .mutation: "Mutation"
        case .destructive: "Destructive"
        case .admin: "Admin"
        case .credentialAccess: "Credential Access"
        case .unknown: "Unknown"
        }
    }
}

public enum MCPToolExecutionPolicy: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case autoAllow
    case requireConfirmation
    case block
}

public enum MCPToolIntegrityStatus: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case new
    case verified
    case changed
}

public struct MCPToolGovernancePolicy: Codable, Sendable, Equatable, Hashable {
    public var riskClass: MCPToolRiskClass
    public var executionPolicy: MCPToolExecutionPolicy
    public var permissionCapability: AgentPermissionCapability
    public var rationale: String
    public var classifierVersion: String
    public var reviewedAt: Date?
    public var reviewedBy: String?

    public init(
        riskClass: MCPToolRiskClass,
        executionPolicy: MCPToolExecutionPolicy,
        permissionCapability: AgentPermissionCapability,
        rationale: String,
        classifierVersion: String = Self.currentClassifierVersion,
        reviewedAt: Date? = nil,
        reviewedBy: String? = nil
    ) {
        self.riskClass = riskClass
        self.executionPolicy = executionPolicy
        self.permissionCapability = permissionCapability
        self.rationale = rationale
        self.classifierVersion = classifierVersion
        self.reviewedAt = reviewedAt
        self.reviewedBy = reviewedBy
    }

    public static let currentClassifierVersion = "mcp-tool-governance-v1.0"

    public static func classify(tool: MCPToolDefinition, source: MCPSourceRuntimeConfiguration) -> MCPToolGovernancePolicy {
        let normalized = [tool.name, tool.description, schemaSearchText(tool.inputSchema)]
            .joined(separator: " ")
            .lowercased()
        let sourceAllowsExternalNetwork = source.allowedCapabilities.contains(.externalNetwork)

        if containsAny(normalized, ["secret", "token", "credential", "password", "api_key", "apikey", "private_key", "ssh_key", "keychain"]) {
            return MCPToolGovernancePolicy(
                riskClass: .credentialAccess,
                executionPolicy: .block,
                permissionCapability: .runDestructiveShellCommand,
                rationale: "Tool name/description/schema suggests credential or secret access; blocked by default."
            )
        }
        if containsAny(normalized, ["admin", "permission", "role", "member", "invite", "billing", "payment", "invoice", "subscription", "webhook", "oauth", "scope"]) {
            return MCPToolGovernancePolicy(
                riskClass: .admin,
                executionPolicy: .requireConfirmation,
                permissionCapability: .runNetworkShellCommand,
                rationale: "Tool may alter administration, billing, identity, or integration state; explicit confirmation required."
            )
        }
        if containsAny(normalized, ["delete", "remove", "destroy", "drop", "truncate", "erase", "revoke", "disable", "deactivate", "purge", "wipe"]) {
            return MCPToolGovernancePolicy(
                riskClass: .destructive,
                executionPolicy: .requireConfirmation,
                permissionCapability: .runDestructiveShellCommand,
                rationale: "Tool appears destructive or revoking; explicit confirmation required."
            )
        }
        if containsAny(normalized, ["create", "update", "edit", "write", "send", "post", "publish", "commit", "merge", "close", "resolve", "assign", "upload", "move", "rename", "patch", "put", "mutate", "execute", "run"]) {
            return MCPToolGovernancePolicy(
                riskClass: .mutation,
                executionPolicy: .requireConfirmation,
                permissionCapability: sourceAllowsExternalNetwork ? .runNetworkShellCommand : .runWorkspaceShellCommand,
                rationale: "Tool appears to change external or workspace state; confirmation required."
            )
        }
        if containsAny(normalized, ["search", "list", "get", "read", "fetch", "query", "find", "lookup", "show", "describe", "inspect"]) {
            return MCPToolGovernancePolicy(
                riskClass: sourceAllowsExternalNetwork ? .externalRead : .read,
                executionPolicy: .autoAllow,
                permissionCapability: sourceAllowsExternalNetwork ? .externalNetwork : .readSession,
                rationale: "Tool appears read-oriented and is allowed within the source capability boundary."
            )
        }
        return MCPToolGovernancePolicy(
            riskClass: .unknown,
            executionPolicy: .requireConfirmation,
            permissionCapability: sourceAllowsExternalNetwork ? .runNetworkShellCommand : .runWorkspaceShellCommand,
            rationale: "Tool intent is unknown; defaulting to explicit confirmation."
        )
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private static func schemaSearchText(_ value: MCPJSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return "null"
        case .array(let values): return values.map(schemaSearchText).joined(separator: " ")
        case .object(let object):
            return object.map { key, value in "\(key) \(schemaSearchText(value))" }.joined(separator: " ")
        }
    }
}

public struct MCPToolDefinitionFingerprint: Codable, Sendable, Equatable, Hashable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String = "sha256", value: String) {
        self.algorithm = algorithm
        self.value = value
    }

    public static func compute(sourceID: String, rawName: String, description: String, inputSchema: MCPJSONValue) -> MCPToolDefinitionFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let schemaData = (try? encoder.encode(inputSchema)) ?? Data("null".utf8)
        let payload = [
            "sourceID=\(sourceID)",
            "rawName=\(rawName)",
            "description=\(description)",
            "inputSchema=\(String(decoding: schemaData, as: UTF8.self))"
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return MCPToolDefinitionFingerprint(value: digest.map { String(format: "%02x", $0) }.joined())
    }
}

public enum MCPToolGovernanceEnforcer: Sendable {
    public static func governedCatalog(
        source: MCPSourceRuntimeConfiguration,
        tools: [MCPToolDefinition],
        previousCatalog: [MCPSourceToolDescriptor] = []
    ) -> [MCPSourceToolDescriptor] {
        let previousByRawName = Dictionary(uniqueKeysWithValues: previousCatalog.map { ($0.rawName, $0) })
        return tools.map { tool in
            let fingerprint = MCPToolDefinitionFingerprint.compute(
                sourceID: source.sourceID,
                rawName: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema
            )
            let previous = previousByRawName[tool.name]
            let integrity: MCPToolIntegrityStatus = {
                guard let previous else { return .new }
                guard let previousFingerprint = previous.definitionFingerprint else { return .changed }
                return previousFingerprint == fingerprint ? .verified : .changed
            }()
            let policy = previous?.governancePolicy ?? MCPToolGovernancePolicy.classify(tool: tool, source: source)
            return MCPSourceToolDescriptor(
                sourceID: source.sourceID,
                name: MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: source.sourceID, rawToolName: tool.name),
                rawName: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
                requiredCapabilities: source.allowedCapabilities,
                governancePolicy: policy,
                definitionFingerprint: fingerprint,
                integrityStatus: integrity
            )
        }.sorted { $0.name < $1.name }
    }
}
