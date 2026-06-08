import Foundation
import ConnorGraphAgent

public enum AppLLMProviderMode: String, Sendable, Equatable, CaseIterable {
    case stub
    case openAICompatible = "openai_compatible"
}

public struct AppLLMSettings: Sendable, Equatable {
    public var baseURLString: String
    public var model: String
    public var hasAPIKey: Bool
    public var providerMode: AppLLMProviderMode

    public init(baseURLString: String, model: String, hasAPIKey: Bool, providerMode: AppLLMProviderMode) {
        self.baseURLString = baseURLString
        self.model = model
        self.hasAPIKey = hasAPIKey
        self.providerMode = providerMode
    }

    public static let `default` = AppLLMSettings(
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        hasAPIKey: false,
        providerMode: .stub
    )
}

public protocol LLMSettingsStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

public final class UserDefaultsLLMSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
}

public struct AppLLMSettingsRepository: @unchecked Sendable {
    public static let keychainService = "ConnorGraphAgent"
    public static let apiKeyAccount = "openai-compatible-api-key"

    private enum Keys {
        static let providerMode = "llm.providerMode"
        static let baseURLString = "llm.baseURLString"
        static let model = "llm.model"
    }

    public var settingsStore: LLMSettingsStore
    public var credentialStore: CredentialStore

    public init(
        settingsStore: LLMSettingsStore = UserDefaultsLLMSettingsStore(),
        credentialStore: CredentialStore = KeychainCredentialStore()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
    }

    public func loadSettings() throws -> AppLLMSettings {
        let defaults = AppLLMSettings.default
        let modeRaw = settingsStore.string(forKey: Keys.providerMode) ?? defaults.providerMode.rawValue
        let mode = AppLLMProviderMode(rawValue: modeRaw) ?? defaults.providerMode
        let apiKey = try credentialStore.readSecret(
            service: Self.keychainService,
            account: Self.apiKeyAccount
        )
        return AppLLMSettings(
            baseURLString: settingsStore.string(forKey: Keys.baseURLString) ?? defaults.baseURLString,
            model: settingsStore.string(forKey: Keys.model) ?? defaults.model,
            hasAPIKey: apiKey?.isEmpty == false,
            providerMode: mode
        )
    }

    public func save(settings: AppLLMSettings, apiKey: String?) throws {
        settingsStore.set(settings.providerMode.rawValue, forKey: Keys.providerMode)
        settingsStore.set(settings.baseURLString, forKey: Keys.baseURLString)
        settingsStore.set(settings.model, forKey: Keys.model)
        if let apiKey, !apiKey.isEmpty {
            try credentialStore.saveSecret(
                apiKey,
                service: Self.keychainService,
                account: Self.apiKeyAccount
            )
        }
    }

    public func clearAPIKey() throws {
        try credentialStore.deleteSecret(
            service: Self.keychainService,
            account: Self.apiKeyAccount
        )
    }

    public func openAICompatibleConfig() throws -> OpenAICompatibleConfig? {
        let settings = try loadSettings()
        guard settings.providerMode == .openAICompatible else { return nil }
        guard let apiKey = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount), !apiKey.isEmpty else {
            return nil
        }
        guard let baseURL = URL(string: settings.baseURLString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(settings.baseURLString)
        }
        return OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: settings.model)
    }
}
