import Foundation
import ConnorGraphAgent

public typealias AppLLMCodexAPIKeyExchange = @Sendable (String) async throws -> String
public typealias OpenAIResponsesHealthCheck = @Sendable (OpenAIResponsesConfig) async throws -> LLMProviderHealthCheckResult
public typealias AnthropicCompatibleHealthCheck = @Sendable (AnthropicCompatibleConfig) async throws -> LLMProviderHealthCheckResult

public struct AppLLMConnectionSetupInput: Sendable, Equatable {
    public var id: String?
    public var kind: AppLLMConnectionKind
    public var name: String
    public var baseURLString: String
    public var model: String
    public var selectedModel: String
    public var validationModel: String
    public var apiKey: String?
    public var oauthTokens: AppLLMOAuthTokens?
    public var anthropicAuthHeaderKind: AnthropicCompatibleAuthHeaderKind
    public var openAIAPIKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind
    public var makeDefault: Bool

    public init(
        id: String? = nil,
        kind: AppLLMConnectionKind,
        name: String,
        baseURLString: String = "",
        model: String = "",
        selectedModel: String = "",
        validationModel: String = "",
        apiKey: String? = nil,
        oauthTokens: AppLLMOAuthTokens? = nil,
        anthropicAuthHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        openAIAPIKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer,
        makeDefault: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURLString = baseURLString
        self.model = model
        self.selectedModel = selectedModel
        self.validationModel = validationModel
        self.apiKey = apiKey
        self.oauthTokens = oauthTokens
        self.anthropicAuthHeaderKind = anthropicAuthHeaderKind
        self.openAIAPIKeyHeaderKind = openAIAPIKeyHeaderKind
        self.makeDefault = makeDefault
    }
}

public struct AppLLMConnectionSetupResult: Sendable, Equatable {
    public var connection: AppLLMConnectionConfig
    public var message: String

    public init(connection: AppLLMConnectionConfig, message: String) {
        self.connection = connection
        self.message = message
    }
}

public enum AppLLMConnectionSetupError: Error, Sendable, Equatable, LocalizedError {
    case missingName
    case invalidBaseURL(String)
    case missingAPIKey
    case missingModel
    case missingOAuthToken(String)
    case healthCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "连接名称不能为空。"
        case .invalidBaseURL(let value):
            return "Base URL 无效：\(value)"
        case .missingAPIKey:
            return "连接缺少 API Key 或可用于运行时的 token。"
        case .missingModel:
            return "连接缺少模型名称。"
        case .missingOAuthToken(let name):
            return "OAuth 结果缺少 \(name)。"
        case .healthCheckFailed(let message):
            return "连接验证失败：\(message)"
        }
    }
}

public struct AppLLMConnectionSetupService: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var openAIResponsesHealthCheck: OpenAIResponsesHealthCheck
    public var openAICompatibleHealthCheck: OpenAICompatibleHealthCheck
    public var anthropicCompatibleHealthCheck: AnthropicCompatibleHealthCheck
    public var codexAPIKeyExchange: AppLLMCodexAPIKeyExchange

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        openAIResponsesHealthCheck: @escaping OpenAIResponsesHealthCheck = { config in
            try await OpenAIResponsesProvider(config: config).healthCheck()
        },
        openAICompatibleHealthCheck: @escaping OpenAICompatibleHealthCheck = { config in
            try await OpenAICompatibleProvider(config: config).healthCheck()
        },
        anthropicCompatibleHealthCheck: @escaping AnthropicCompatibleHealthCheck = { config in
            try await AnthropicCompatibleProvider(config: config).healthCheck()
        },
        codexAPIKeyExchange: @escaping AppLLMCodexAPIKeyExchange = { idToken in
            try await AppLLMOAuthService.shared.exchangeChatGPTIDTokenForAPIKey(idToken)
        }
    ) {
        self.settingsRepository = settingsRepository
        self.openAIResponsesHealthCheck = openAIResponsesHealthCheck
        self.openAICompatibleHealthCheck = openAICompatibleHealthCheck
        self.anthropicCompatibleHealthCheck = anthropicCompatibleHealthCheck
        self.codexAPIKeyExchange = codexAPIKeyExchange
    }

    public func setupConnection(_ input: AppLLMConnectionSetupInput) async throws -> AppLLMConnectionSetupResult {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppLLMConnectionSetupError.missingName }

        switch input.kind {
        case .openAIResponses:
            return try await setupOpenAIResponses(input, name: name)
        case .openAICompatible:
            return try await setupOpenAICompatible(input, name: name)
        case .chatGPTCodex:
            return try await setupChatGPTCodex(input, name: name)
        case .githubCopilot:
            return try await setupGitHubCopilot(input, name: name)
        case .anthropicCompatible:
            return try await setupAnthropicCompatible(input, name: name)
        }
    }

    private func setupOpenAIResponses(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString), !baseURLString.isEmpty else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model)
        let validationModel = normalizedValidationModel(input.validationModel, selectedModel: input.selectedModel, model: model)
        guard !validationModel.isEmpty else { throw AppLLMConnectionSetupError.missingModel }
        let suppliedAPIKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !suppliedAPIKey.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let config = OpenAIResponsesConfig(baseURL: baseURL, apiKey: suppliedAPIKey, model: validationModel, apiKeyHeaderKind: input.openAIAPIKeyHeaderKind)
        let health = try await openAIResponsesHealthCheck(config)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }

        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "openai-responses"),
            name: name,
            providerMode: .openAIResponses,
            connectionKind: .openAIResponses,
            baseURLString: baseURLString,
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: true,
            extraHTTPHeaders: openAICompatibleMetadataHeaders(for: input.openAIAPIKeyHeaderKind)
        )
        try settingsRepository.saveConnection(connection, apiKey: suppliedAPIKey, oauthTokens: input.oauthTokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "OpenAI Responses 连接验证成功：\(health.model)")
    }

    private func setupOpenAICompatible(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString), !baseURLString.isEmpty else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model)
        let validationModel = normalizedValidationModel(input.validationModel, selectedModel: input.selectedModel, model: model)
        guard !validationModel.isEmpty else { throw AppLLMConnectionSetupError.missingModel }
        let suppliedAPIKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = suppliedAPIKey.isEmpty && Self.isLocalBaseURL(baseURL) ? "connor-local-model" : suppliedAPIKey
        guard !apiKey.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let config = OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: validationModel, apiKeyHeaderKind: input.openAIAPIKeyHeaderKind)
        let health = try await openAICompatibleHealthCheck(config)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }

        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "openai-compatible"),
            name: name,
            providerMode: .openAICompatible,
            connectionKind: .openAICompatible,
            baseURLString: baseURLString,
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: true,
            extraHTTPHeaders: openAICompatibleMetadataHeaders(for: input.openAIAPIKeyHeaderKind)
        )
        try settingsRepository.saveConnection(connection, apiKey: apiKey, oauthTokens: input.oauthTokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "OpenAI Compatible 连接验证成功：\(health.model)")
    }

    private func setupChatGPTCodex(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        guard let tokens = input.oauthTokens else { throw AppLLMConnectionSetupError.missingOAuthToken("oauth tokens") }
        guard let idToken = tokens.idToken?.trimmingCharacters(in: .whitespacesAndNewlines), !idToken.isEmpty else {
            throw AppLLMConnectionSetupError.missingOAuthToken("id_token")
        }
        let apiKey: String
        if let supplied = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !supplied.isEmpty {
            apiKey = supplied
        } else {
            apiKey = try await codexAPIKeyExchange(idToken)
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "https://api.openai.com/v1" : input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString) else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model).isEmpty ? "gpt-4o-mini" : normalizedModel(input.model)
        let config = OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: model)
        let health = try await openAICompatibleHealthCheck(config)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }

        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "codex-chatgpt-plus"),
            name: name,
            providerMode: .openAICompatible,
            connectionKind: .chatGPTCodex,
            baseURLString: baseURLString,
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: true
        )
        try settingsRepository.saveConnection(connection, apiKey: apiKey, oauthTokens: tokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "Codex · ChatGPT 连接验证成功：\(health.model)")
    }

    private func setupGitHubCopilot(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        guard let tokens = input.oauthTokens else { throw AppLLMConnectionSetupError.missingOAuthToken("copilot token") }
        let runtimeToken = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? input.apiKey!.trimmingCharacters(in: .whitespacesAndNewlines)
            : tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runtimeToken.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }
        let derivedBaseURL = AppLLMOAuthService.copilotBaseURL(from: runtimeToken)
        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (derivedBaseURL ?? "https://api.githubcopilot.com")
            : input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString) else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model).isEmpty ? "gpt-4.1" : normalizedModel(input.model)
        let extraHeaders = [
            "User-Agent": "GitHubCopilotChat/0.35.0",
            "Editor-Version": "vscode/1.107.0",
            "Editor-Plugin-Version": "copilot-chat/0.35.0",
            "Copilot-Integration-Id": "vscode-chat"
        ]
        let config = OpenAICompatibleConfig(baseURL: baseURL, apiKey: runtimeToken, model: model, extraHeaders: extraHeaders)
        let health = try await openAICompatibleHealthCheck(config)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }

        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "github-copilot"),
            name: name,
            providerMode: .openAICompatible,
            connectionKind: .githubCopilot,
            baseURLString: baseURLString,
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: true,
            extraHTTPHeaders: extraHeaders
        )
        try settingsRepository.saveConnection(connection, apiKey: runtimeToken, oauthTokens: tokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "GitHub Copilot 连接验证成功：\(health.model)")
    }

    private func setupAnthropicCompatible(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString), !baseURLString.isEmpty else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model)
        let validationModel = normalizedValidationModel(input.validationModel, selectedModel: input.selectedModel, model: model)
        guard !validationModel.isEmpty else { throw AppLLMConnectionSetupError.missingModel }
        let apiKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let config = AnthropicCompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: validationModel, authHeaderKind: input.anthropicAuthHeaderKind)
        let health = try await anthropicCompatibleHealthCheck(config)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }

        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "anthropic-compatible"),
            name: name,
            providerMode: .anthropicMessages,
            connectionKind: .anthropicCompatible,
            baseURLString: baseURLString,
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: true,
            extraHTTPHeaders: [AppLLMSettingsRepository.anthropicAuthHeaderKindMetadataKey: input.anthropicAuthHeaderKind.rawValue]
        )
        try settingsRepository.saveConnection(connection, apiKey: apiKey, oauthTokens: input.oauthTokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "Anthropic Compatible 连接验证成功：\(health.model)")
    }

    private func openAICompatibleMetadataHeaders(for headerKind: OpenAICompatibleAPIKeyHeaderKind) -> [String: String] {
        guard headerKind != .bearer else { return [:] }
        return [AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey: headerKind.rawValue]
    }

    private static func isLocalBaseURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func normalizedID(_ id: String?, fallbackPrefix: String) -> String {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return "\(fallbackPrefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func normalizedModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedValidationModel(_ validationModel: String, selectedModel: String, model: String) -> String {
        let explicitValidationModel = validationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitValidationModel.isEmpty { return explicitValidationModel }
        let firstConfiguredModel = AppLLMConnectionConfig.firstModel(in: model)
        if !firstConfiguredModel.isEmpty { return firstConfiguredModel }
        return selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSelectedModel(_ selectedModel: String, model: String) -> String {
        let trimmed = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLLMConnectionConfig.firstModel(in: model) : trimmed
    }

}

public extension AppLLMSettingsRepository {
    func saveConnection(
        _ connection: AppLLMConnectionConfig,
        apiKey: String? = nil,
        oauthTokens: AppLLMOAuthTokens? = nil,
        makeDefault: Bool = true
    ) throws {
        let current = (try? loadSettings()) ?? .default
        var connections = current.connections
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        let settings = AppLLMSettings(
            connections: connections,
            defaultConnectionID: makeDefault ? connection.id : current.defaultConnectionID
        )
        try save(settings: settings, apiKey: apiKey)
        if let oauthTokens {
            try saveOAuthTokens(oauthTokens, connectionID: connection.id)
        }
    }
}
