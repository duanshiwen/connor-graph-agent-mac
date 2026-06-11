import Foundation
import ConnorGraphAgent

public enum AppLLMProviderMode: String, Sendable, Equatable, CaseIterable {
    case stub
    case openAICompatible = "openai_compatible"
    case governedClaudeSidecar = "governed_claude_sidecar"
}

public struct AppLLMSettings: Sendable, Equatable {
    public var baseURLString: String
    public var model: String
    public var hasAPIKey: Bool
    public var providerMode: AppLLMProviderMode
    public var sidecarExecutablePath: String
    public var sidecarArguments: String
    public var sidecarWorkingDirectoryPath: String
    public var sidecarPermissionMode: AgentPermissionMode

    public init(
        baseURLString: String,
        model: String,
        hasAPIKey: Bool,
        providerMode: AppLLMProviderMode,
        sidecarExecutablePath: String = "",
        sidecarArguments: String = "",
        sidecarWorkingDirectoryPath: String = "",
        sidecarPermissionMode: AgentPermissionMode = .readOnly
    ) {
        self.baseURLString = baseURLString
        self.model = model
        self.hasAPIKey = hasAPIKey
        self.providerMode = providerMode
        self.sidecarExecutablePath = sidecarExecutablePath
        self.sidecarArguments = sidecarArguments
        self.sidecarWorkingDirectoryPath = sidecarWorkingDirectoryPath
        self.sidecarPermissionMode = sidecarPermissionMode == .allowAll ? .readOnly : sidecarPermissionMode
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
        static let sidecarExecutablePath = "llm.sidecar.executablePath"
        static let sidecarArguments = "llm.sidecar.arguments"
        static let sidecarWorkingDirectoryPath = "llm.sidecar.workingDirectoryPath"
        static let sidecarPermissionMode = "llm.sidecar.permissionMode"
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
        let sidecarPermissionRaw = settingsStore.string(forKey: Keys.sidecarPermissionMode) ?? defaults.sidecarPermissionMode.rawValue
        let sidecarPermissionMode = AgentPermissionMode(rawValue: sidecarPermissionRaw) ?? defaults.sidecarPermissionMode
        return AppLLMSettings(
            baseURLString: settingsStore.string(forKey: Keys.baseURLString) ?? defaults.baseURLString,
            model: settingsStore.string(forKey: Keys.model) ?? defaults.model,
            hasAPIKey: apiKey?.isEmpty == false,
            providerMode: mode,
            sidecarExecutablePath: settingsStore.string(forKey: Keys.sidecarExecutablePath) ?? defaults.sidecarExecutablePath,
            sidecarArguments: settingsStore.string(forKey: Keys.sidecarArguments) ?? defaults.sidecarArguments,
            sidecarWorkingDirectoryPath: settingsStore.string(forKey: Keys.sidecarWorkingDirectoryPath) ?? defaults.sidecarWorkingDirectoryPath,
            sidecarPermissionMode: sidecarPermissionMode
        )
    }

    public func save(settings: AppLLMSettings, apiKey: String?) throws {
        settingsStore.set(settings.providerMode.rawValue, forKey: Keys.providerMode)
        settingsStore.set(settings.baseURLString, forKey: Keys.baseURLString)
        settingsStore.set(settings.model, forKey: Keys.model)
        settingsStore.set(settings.sidecarExecutablePath, forKey: Keys.sidecarExecutablePath)
        settingsStore.set(settings.sidecarArguments, forKey: Keys.sidecarArguments)
        settingsStore.set(settings.sidecarWorkingDirectoryPath, forKey: Keys.sidecarWorkingDirectoryPath)
        settingsStore.set(settings.sidecarPermissionMode == .allowAll ? AgentPermissionMode.readOnly.rawValue : settings.sidecarPermissionMode.rawValue, forKey: Keys.sidecarPermissionMode)
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
