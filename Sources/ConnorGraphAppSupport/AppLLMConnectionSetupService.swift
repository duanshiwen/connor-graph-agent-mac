import Foundation
import ConnorGraphAgent

public typealias AppLLMConnectionSidecarValidator = @Sendable (AppLLMConnectionConfig) async throws -> LLMProviderHealthCheckResult
public typealias AppLLMCodexAPIKeyExchange = @Sendable (String) async throws -> String
public typealias AnthropicCompatibleHealthCheck = @Sendable (AnthropicCompatibleConfig) async throws -> LLMProviderHealthCheckResult

public struct AppLLMConnectionSetupInput: Sendable, Equatable {
    public var id: String?
    public var kind: AppLLMConnectionKind
    public var name: String
    public var baseURLString: String
    public var model: String
    public var selectedModel: String
    public var apiKey: String?
    public var oauthTokens: AppLLMOAuthTokens?
    public var sidecarExecutablePath: String
    public var sidecarArguments: String
    public var sidecarWorkingDirectoryPath: String
    public var sidecarPermissionMode: AgentPermissionMode
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
        apiKey: String? = nil,
        oauthTokens: AppLLMOAuthTokens? = nil,
        sidecarExecutablePath: String = "",
        sidecarArguments: String = "",
        sidecarWorkingDirectoryPath: String = "",
        sidecarPermissionMode: AgentPermissionMode = .readOnly,
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
        self.apiKey = apiKey
        self.oauthTokens = oauthTokens
        self.sidecarExecutablePath = sidecarExecutablePath
        self.sidecarArguments = sidecarArguments
        self.sidecarWorkingDirectoryPath = sidecarWorkingDirectoryPath
        self.sidecarPermissionMode = sidecarPermissionMode
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
    case missingSidecarExecutablePath
    case sidecarExecutableNotFound(String)
    case sidecarExecutableNotExecutable(String)
    case unsafePermissionMode
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
        case .missingSidecarExecutablePath:
            return "Claude 连接缺少 sidecar executable path。"
        case .sidecarExecutableNotFound(let path):
            return "Claude sidecar executable 不存在：\(path)"
        case .sidecarExecutableNotExecutable(let path):
            return "Claude sidecar executable 不可执行：\(path)"
        case .unsafePermissionMode:
            return "Claude Sidecar 连接不允许 allowAll 权限模式。"
        case .healthCheckFailed(let message):
            return "连接验证失败：\(message)"
        }
    }
}

public struct AppLLMConnectionSetupService: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var openAICompatibleHealthCheck: OpenAICompatibleHealthCheck
    public var anthropicCompatibleHealthCheck: AnthropicCompatibleHealthCheck
    public var sidecarValidator: AppLLMConnectionSidecarValidator
    public var codexAPIKeyExchange: AppLLMCodexAPIKeyExchange

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        openAICompatibleHealthCheck: @escaping OpenAICompatibleHealthCheck = { config in
            try await OpenAICompatibleProvider(config: config).healthCheck()
        },
        anthropicCompatibleHealthCheck: @escaping AnthropicCompatibleHealthCheck = { config in
            try await AnthropicCompatibleProvider(config: config).healthCheck()
        },
        sidecarValidator: @escaping AppLLMConnectionSidecarValidator = { connection in
            try Self.defaultSidecarValidation(connection: connection)
        },
        codexAPIKeyExchange: @escaping AppLLMCodexAPIKeyExchange = { idToken in
            try await AppLLMOAuthService.shared.exchangeChatGPTIDTokenForAPIKey(idToken)
        }
    ) {
        self.settingsRepository = settingsRepository
        self.openAICompatibleHealthCheck = openAICompatibleHealthCheck
        self.anthropicCompatibleHealthCheck = anthropicCompatibleHealthCheck
        self.sidecarValidator = sidecarValidator
        self.codexAPIKeyExchange = codexAPIKeyExchange
    }

    public func setupConnection(_ input: AppLLMConnectionSetupInput) async throws -> AppLLMConnectionSetupResult {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppLLMConnectionSetupError.missingName }

        switch input.kind {
        case .openAICompatible:
            return try await setupOpenAICompatible(input, name: name)
        case .claudeSidecar:
            return try await setupClaudeSidecar(input, name: name)
        case .chatGPTCodex:
            return try await setupChatGPTCodex(input, name: name)
        case .githubCopilot:
            return try await setupGitHubCopilot(input, name: name)
        case .anthropicCompatible:
            return try await setupAnthropicCompatible(input, name: name)
        }
    }

    private func setupOpenAICompatible(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        let baseURLString = input.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLString), !baseURLString.isEmpty else { throw AppLLMConnectionSetupError.invalidBaseURL(baseURLString) }
        let model = normalizedModel(input.model)
        guard !model.isEmpty else { throw AppLLMConnectionSetupError.missingModel }
        let suppliedAPIKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = suppliedAPIKey.isEmpty && Self.isLocalBaseURL(baseURL) ? "connor-local-model" : suppliedAPIKey
        guard !apiKey.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let config = OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: model, apiKeyHeaderKind: input.openAIAPIKeyHeaderKind)
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

    private func setupClaudeSidecar(_ input: AppLLMConnectionSetupInput, name: String) async throws -> AppLLMConnectionSetupResult {
        let executablePath = input.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else { throw AppLLMConnectionSetupError.missingSidecarExecutablePath }
        guard FileManager.default.fileExists(atPath: executablePath) else { throw AppLLMConnectionSetupError.sidecarExecutableNotFound(executablePath) }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { throw AppLLMConnectionSetupError.sidecarExecutableNotExecutable(executablePath) }
        guard input.sidecarPermissionMode != .allowAll else { throw AppLLMConnectionSetupError.unsafePermissionMode }

        let model = normalizedModel(input.model).isEmpty ? "claude-sdk-default" : normalizedModel(input.model)
        let connection = AppLLMConnectionConfig(
            id: normalizedID(input.id, fallbackPrefix: "claude-sidecar"),
            name: name,
            providerMode: .governedClaudeSidecar,
            connectionKind: .claudeSidecar,
            baseURLString: "",
            model: model,
            selectedModel: normalizedSelectedModel(input.selectedModel, model: model),
            hasAPIKey: input.oauthTokens != nil,
            sidecarExecutablePath: executablePath,
            sidecarArguments: input.sidecarArguments.trimmingCharacters(in: .whitespacesAndNewlines),
            sidecarWorkingDirectoryPath: input.sidecarWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines),
            sidecarPermissionMode: input.sidecarPermissionMode
        )
        let health = try await sidecarValidator(connection)
        guard health.ok else { throw AppLLMConnectionSetupError.healthCheckFailed(health.message) }
        try settingsRepository.saveConnection(connection, apiKey: nil, oauthTokens: input.oauthTokens, makeDefault: input.makeDefault)
        return AppLLMConnectionSetupResult(connection: connection, message: "Claude SDK sidecar 连接验证成功。")
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
        guard !model.isEmpty else { throw AppLLMConnectionSetupError.missingModel }
        let apiKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { throw AppLLMConnectionSetupError.missingAPIKey }

        let config = AnthropicCompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: model, authHeaderKind: input.anthropicAuthHeaderKind)
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

    private func normalizedSelectedModel(_ selectedModel: String, model: String) -> String {
        let trimmed = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLLMConnectionConfig.firstModel(in: model) : trimmed
    }

    public static func defaultSidecarValidation(connection: AppLLMConnectionConfig) throws -> LLMProviderHealthCheckResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: connection.sidecarExecutablePath)
        process.arguments = connection.sidecarArguments
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let cwd = connection.sidecarWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cwd.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true) }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data("{\"health\":{}}\n".utf8))
        try? stdin.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard output.contains("\"sidecarHealth\"") && output.contains("\"status\":\"ok\"") else {
            throw AppLLMConnectionSetupError.healthCheckFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output : errorText)
        }
        return LLMProviderHealthCheckResult(ok: true, model: connection.effectiveModel, message: "Claude sidecar health OK.")
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
