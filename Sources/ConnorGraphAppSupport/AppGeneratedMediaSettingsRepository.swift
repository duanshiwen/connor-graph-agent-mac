import Foundation
import ConnorGraphAgent

public enum AppGeneratedMediaProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case openAIResponses = "openai_responses"
    case openAIImages = "openai_images"
    case geminiImage = "gemini_image"
    case blackForestLabs = "black_forest_labs"
    case stabilityAI = "stability_ai"

    public var displayName: String {
        switch self {
        case .openAIResponses: return "OpenAI Responses"
        case .openAIImages: return "OpenAI Images"
        case .geminiImage: return "Google Gemini Image"
        case .blackForestLabs: return "Black Forest Labs"
        case .stabilityAI: return "Stability AI"
        }
    }
}

public struct AppGeneratedMediaConnectionConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var providerKind: AppGeneratedMediaProviderKind
    public var baseURLString: String
    public var model: String
    public var hasAPIKey: Bool
    public var extraHTTPHeaders: [String: String]

    public init(
        id: String,
        name: String,
        providerKind: AppGeneratedMediaProviderKind,
        baseURLString: String,
        model: String,
        hasAPIKey: Bool = false,
        extraHTTPHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.providerKind = providerKind
        self.baseURLString = baseURLString
        self.model = model
        self.hasAPIKey = hasAPIKey
        self.extraHTTPHeaders = extraHTTPHeaders
    }

    public var isConfigured: Bool {
        hasAPIKey
            && URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AppGeneratedMediaSettings: Codable, Sendable, Equatable {
    public var connections: [AppGeneratedMediaConnectionConfig]
    public var defaultImageConnectionID: String?

    public init(connections: [AppGeneratedMediaConnectionConfig] = [], defaultImageConnectionID: String? = nil) {
        self.connections = connections
        self.defaultImageConnectionID = defaultImageConnectionID
    }

    public var defaultImageConnection: AppGeneratedMediaConnectionConfig? {
        guard let defaultImageConnectionID else { return nil }
        return connections.first { $0.id == defaultImageConnectionID }
    }

    public static let `default` = AppGeneratedMediaSettings()
}

public struct AppGeneratedMediaSettingsRepository: @unchecked Sendable {
    public static let credentialNamespace = "ConnorGraphAgent.GeneratedMedia"
    private static let settingsKey = "generatedMedia.connections"
    private static let defaultImageConnectionIDKey = "generatedMedia.defaultImageConnectionID"

    public var settingsStore: LLMSettingsStore
    public var credentialStore: CredentialStore

    public init(
        settingsStore: LLMSettingsStore = UserDefaultsLLMSettingsStore(),
        credentialStore: CredentialStore = LocalEncryptedCredentialStore()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
    }

    public static func apiKeyAccount(for connectionID: String) -> String { "media-connection-\(connectionID)-api-key" }

    public func loadSettings() throws -> AppGeneratedMediaSettings {
        guard let raw = settingsStore.string(forKey: Self.settingsKey), let data = raw.data(using: .utf8) else { return .default }
        let decoded = try JSONDecoder().decode([AppGeneratedMediaConnectionConfig].self, from: data)
        let hydrated = try decoded.map { connection in
            var copy = connection
            copy.hasAPIKey = try apiKey(for: connection.id)?.isEmpty == false
            return copy
        }
        return AppGeneratedMediaSettings(
            connections: hydrated,
            defaultImageConnectionID: settingsStore.string(forKey: Self.defaultImageConnectionIDKey)
        )
    }

    public func save(settings: AppGeneratedMediaSettings) throws {
        let sanitized = settings.connections.map { connection in
            var copy = connection
            copy.hasAPIKey = false
            return copy
        }
        let data = try JSONEncoder().encode(sanitized)
        settingsStore.set(String(decoding: data, as: UTF8.self), forKey: Self.settingsKey)
        settingsStore.set(settings.defaultImageConnectionID ?? "", forKey: Self.defaultImageConnectionIDKey)
    }

    public func saveAPIKey(_ apiKey: String, connectionID: String) throws {
        guard !apiKey.isEmpty else { return }
        try credentialStore.saveSecret(apiKey, service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID))
    }

    public func apiKey(for connectionID: String) throws -> String? {
        try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID))
    }

    public func clearAPIKey(connectionID: String) throws {
        try credentialStore.deleteSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID))
    }
}

public enum AppGeneratedMediaHealthStatus: Sendable, Equatable {
    case ready
    case missingCredential
    case invalidBaseURL
    case missingModel
}

public enum AppGeneratedMediaConnectionHealthChecker {
    public static func status(for connection: AppGeneratedMediaConnectionConfig) -> AppGeneratedMediaHealthStatus {
        if !connection.hasAPIKey { return .missingCredential }
        if URL(string: connection.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return .invalidBaseURL }
        if connection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingModel }
        return .ready
    }
}
