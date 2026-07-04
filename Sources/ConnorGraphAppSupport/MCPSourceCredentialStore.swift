import Foundation
import ConnorGraphCore

public struct MCPSourceCredentialBinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String { environmentVariable }
    public var label: String
    public var environmentVariable: String

    public init(label: String, environmentVariable: String) {
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.environmentVariable = environmentVariable.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum MCPSourceCredentialStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedRequirement(ProductOSCredentialRequirement)
    case missingBinding(String)
    case invalidEnvironmentVariable(String)
    case missingCredential(sourceID: String, environmentVariable: String)

    public var description: String {
        switch self {
        case .unsupportedRequirement(let requirement): "unsupportedRequirement: \(requirement.rawValue)"
        case .missingBinding(let sourceID): "missingCredentialBinding: \(sourceID)"
        case .invalidEnvironmentVariable(let name): "invalidEnvironmentVariable: \(name)"
        case .missingCredential(let sourceID, let environmentVariable): "missingCredential: \(sourceID) requires secret for \(environmentVariable)"
        }
    }
}

/// Connor-owned credential boundary for MCP sources.
///
/// Source runtime JSON stores only credential requirements and environment binding names.
/// Secret values are stored in the injected `CredentialStore` and are materialized only as
/// source-scoped subprocess environment overrides immediately before stdio MCP startup.
public struct MCPSourceCredentialStore: Sendable {
    public static let keychainService = "ConnorGraphAgent.MCPSourceCredentials"

    public var credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = LocalEncryptedCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func saveSecret(_ secret: String, sourceID: String, environmentVariable: String) throws {
        let normalized = try Self.normalizedEnvironmentVariable(environmentVariable)
        try credentialStore.saveSecret(secret, service: Self.keychainService, account: Self.account(sourceID: sourceID, environmentVariable: normalized))
    }

    public func readSecret(sourceID: String, environmentVariable: String) throws -> String? {
        let normalized = try Self.normalizedEnvironmentVariable(environmentVariable)
        return try credentialStore.readSecret(service: Self.keychainService, account: Self.account(sourceID: sourceID, environmentVariable: normalized))
    }

    public func deleteSecret(sourceID: String, environmentVariable: String) throws {
        let normalized = try Self.normalizedEnvironmentVariable(environmentVariable)
        try credentialStore.deleteSecret(service: Self.keychainService, account: Self.account(sourceID: sourceID, environmentVariable: normalized))
    }

    public func deleteSecrets(sourceID: String, bindings: [MCPSourceCredentialBinding]) throws {
        for binding in bindings {
            try deleteSecret(sourceID: sourceID, environmentVariable: binding.environmentVariable)
        }
    }

    public func hasRequiredCredentials(for configuration: MCPSourceRuntimeConfiguration) throws -> Bool {
        guard configuration.credentialRequirement != .none else { return true }
        let bindings = try Self.validatedBindings(for: configuration)
        for binding in bindings {
            if try readSecret(sourceID: configuration.sourceID, environmentVariable: binding.environmentVariable) == nil {
                return false
            }
        }
        return true
    }

    public func environmentOverrides(for configuration: MCPSourceRuntimeConfiguration) throws -> [String: String] {
        guard configuration.credentialRequirement != .none else { return [:] }
        let bindings = try Self.validatedBindings(for: configuration)
        var environment: [String: String] = [:]
        for binding in bindings {
            let env = try Self.normalizedEnvironmentVariable(binding.environmentVariable)
            environment[env] = try requiredSecret(sourceID: configuration.sourceID, environmentVariable: env)
        }
        return environment
    }

    public func httpHeaders(for configuration: MCPSourceRuntimeConfiguration) throws -> [String: String] {
        guard configuration.credentialRequirement != .none else { return [:] }
        let bindings = try Self.validatedBindings(for: configuration)
        switch configuration.credentialRequirement {
        case .bearerToken:
            guard let binding = bindings.first else { throw MCPSourceCredentialStoreError.missingBinding(configuration.sourceID) }
            let secret = try requiredSecret(sourceID: configuration.sourceID, environmentVariable: binding.environmentVariable)
            return ["Authorization": "Bearer \(secret)"]
        case .apiKeyHeader:
            guard let binding = bindings.first else { throw MCPSourceCredentialStoreError.missingBinding(configuration.sourceID) }
            let headerName = binding.label.isEmpty ? binding.environmentVariable : binding.label
            let secret = try requiredSecret(sourceID: configuration.sourceID, environmentVariable: binding.environmentVariable)
            return [headerName: secret]
        case .multiHeader:
            var headers: [String: String] = [:]
            for binding in bindings {
                let headerName = binding.label.isEmpty ? binding.environmentVariable : binding.label
                headers[headerName] = try requiredSecret(sourceID: configuration.sourceID, environmentVariable: binding.environmentVariable)
            }
            return headers
        case .none:
            return [:]
        case .basic, .apiKeyQuery, .oauth:
            throw MCPSourceCredentialStoreError.unsupportedRequirement(configuration.credentialRequirement)
        }
    }

    private func requiredSecret(sourceID: String, environmentVariable: String) throws -> String {
        let env = try Self.normalizedEnvironmentVariable(environmentVariable)
        guard let secret = try readSecret(sourceID: sourceID, environmentVariable: env), !secret.isEmpty else {
            throw MCPSourceCredentialStoreError.missingCredential(sourceID: sourceID, environmentVariable: env)
        }
        return secret
    }

    public static func validatedBindings(for configuration: MCPSourceRuntimeConfiguration) throws -> [MCPSourceCredentialBinding] {
        guard configuration.credentialRequirement != .none else { return [] }
        switch configuration.credentialRequirement {
        case .bearerToken, .apiKeyHeader, .multiHeader:
            break
        case .none:
            return []
        case .basic, .apiKeyQuery, .oauth:
            throw MCPSourceCredentialStoreError.unsupportedRequirement(configuration.credentialRequirement)
        }
        guard !configuration.credentialBindings.isEmpty else {
            throw MCPSourceCredentialStoreError.missingBinding(configuration.sourceID)
        }
        return try configuration.credentialBindings.map { binding in
            MCPSourceCredentialBinding(
                label: binding.label.isEmpty ? binding.environmentVariable : binding.label,
                environmentVariable: try normalizedEnvironmentVariable(binding.environmentVariable)
            )
        }
    }

    public static func normalizedEnvironmentVariable(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) != nil else {
            throw MCPSourceCredentialStoreError.invalidEnvironmentVariable(name)
        }
        return trimmed
    }

    public static func account(sourceID: String, environmentVariable: String) -> String {
        "mcp-source:\(sourceID):env:\(environmentVariable)"
    }
}
