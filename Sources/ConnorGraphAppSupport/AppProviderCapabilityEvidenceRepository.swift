import Foundation
import CryptoKit

public enum AppProviderCapabilityID: String, Codable, Sendable, Equatable, CaseIterable {
    case chatCompletions = "chat_completions"
    case functionCalling = "function_calling"
    case responses
    case hostedImageGeneration = "hosted_image_generation"
}

public enum AppProviderCapabilityStatus: String, Codable, Sendable, Equatable {
    case verified
    case unsupported
    case unknown
    case expired
}

public struct AppProviderCapabilityEvidence: Codable, Sendable, Equatable, Identifiable {
    public var capability: AppProviderCapabilityID
    public var status: AppProviderCapabilityStatus
    public var verifiedAt: Date
    public var endpointFamily: String
    public var modelID: String
    public var bindingFingerprint: String
    public var protocolVersion: Int
    public var sanitizedDiagnostic: String?

    public var id: String { capability.rawValue }

    public init(
        capability: AppProviderCapabilityID,
        status: AppProviderCapabilityStatus,
        verifiedAt: Date = Date(),
        endpointFamily: String,
        modelID: String,
        bindingFingerprint: String,
        protocolVersion: Int = AppProviderCapabilityEvidenceRepository.currentProtocolVersion,
        sanitizedDiagnostic: String? = nil
    ) {
        self.capability = capability
        self.status = status
        self.verifiedAt = verifiedAt
        self.endpointFamily = endpointFamily
        self.modelID = modelID
        self.bindingFingerprint = bindingFingerprint
        self.protocolVersion = protocolVersion
        self.sanitizedDiagnostic = sanitizedDiagnostic.map { String($0.prefix(500)) }
    }
}

public struct AppProviderCapabilitySnapshot: Codable, Sendable, Equatable {
    public var connectionID: String
    public var evidence: [AppProviderCapabilityEvidence]

    public init(connectionID: String, evidence: [AppProviderCapabilityEvidence] = []) {
        self.connectionID = connectionID
        self.evidence = evidence
    }

    public func evidence(for capability: AppProviderCapabilityID) -> AppProviderCapabilityEvidence? {
        evidence.first { $0.capability == capability }
    }
}

public struct AppProviderCapabilityEvidenceRepository: @unchecked Sendable {
    public static let currentProtocolVersion = 1
    private static let settingsKey = "llm.providerCapabilityEvidence"

    public var settingsStore: LLMSettingsStore
    public var credentialStore: CredentialStore

    public init(
        settingsStore: LLMSettingsStore = UserDefaultsLLMSettingsStore(),
        credentialStore: CredentialStore = LocalEncryptedCredentialStore()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
    }

    public func loadAll() -> [AppProviderCapabilitySnapshot] {
        guard let raw = settingsStore.string(forKey: Self.settingsKey),
              let data = raw.data(using: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AppProviderCapabilitySnapshot].self, from: data)) ?? []
    }

    public func save(_ snapshot: AppProviderCapabilitySnapshot) throws {
        var all = loadAll().filter { $0.connectionID != snapshot.connectionID }
        all.append(snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        settingsStore.set(String(decoding: try encoder.encode(all), as: UTF8.self), forKey: Self.settingsKey)
    }

    public func replaceEvidence(_ evidence: AppProviderCapabilityEvidence, connectionID: String) throws {
        var snapshot = loadAll().first { $0.connectionID == connectionID }
            ?? AppProviderCapabilitySnapshot(connectionID: connectionID)
        snapshot.evidence.removeAll { $0.capability == evidence.capability }
        snapshot.evidence.append(evidence)
        try save(snapshot)
    }

    public func invalidate(connectionID: String) throws {
        try save(AppProviderCapabilitySnapshot(connectionID: connectionID))
    }

    public func effectiveEvidence(
        for capability: AppProviderCapabilityID,
        connection: AppLLMConnectionConfig
    ) throws -> AppProviderCapabilityEvidence? {
        guard var evidence = loadAll().first(where: { $0.connectionID == connection.id })?.evidence(for: capability)
        else { return nil }
        let apiKey = try credentialStore.readSecret(
            service: AppLLMSettingsRepository.credentialNamespace,
            account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id)
        ) ?? ""
        guard evidence.protocolVersion == Self.currentProtocolVersion,
              evidence.bindingFingerprint == Self.bindingFingerprint(connection: connection, credential: apiKey)
        else {
            evidence.status = .expired
            return evidence
        }
        return evidence
    }

    public static func bindingFingerprint(connection: AppLLMConnectionConfig, credential: String) -> String {
        let normalizedURL = connection.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let headers = connection.extraHTTPHeaders
            .filter { key, _ in
                !key.lowercased().contains("authorization") && !key.lowercased().contains("api-key")
            }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key.lowercased()):\($0.value)" }
            .joined(separator: "\n")
        let credentialDigest = digest(credential)
        return digest([
            connection.id,
            connection.providerMode.rawValue,
            connection.connectionKind.rawValue,
            normalizedURL,
            connection.effectiveModel,
            headers,
            credentialDigest,
            String(currentProtocolVersion)
        ].joined(separator: "\u{1f}"))
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
