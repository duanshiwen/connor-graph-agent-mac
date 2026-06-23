import Foundation
import ConnorGraphAgent

public enum AppLLMProviderHealthCheckStatus: Sendable, Equatable {
    case notConfigured
    case success
    case failed
}

public struct AppLLMProviderHealthCheckResult: Sendable, Equatable {
    public var status: AppLLMProviderHealthCheckStatus
    public var message: String

    public init(status: AppLLMProviderHealthCheckStatus, message: String) {
        self.status = status
        self.message = message
    }
}

public typealias OpenAICompatibleHealthCheck = @Sendable (OpenAICompatibleConfig) async throws -> LLMProviderHealthCheckResult

public struct AppLLMProviderHealthChecker: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var openAIResponsesHealthCheck: OpenAIResponsesHealthCheck
    public var openAICompatibleHealthCheck: OpenAICompatibleHealthCheck

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        openAIResponsesHealthCheck: @escaping OpenAIResponsesHealthCheck = { config in
            try await OpenAIResponsesProvider(config: config).healthCheck()
        },
        openAICompatibleHealthCheck: @escaping OpenAICompatibleHealthCheck = { config in
            try await OpenAICompatibleProvider(config: config).healthCheck()
        }
    ) {
        self.settingsRepository = settingsRepository
        self.openAIResponsesHealthCheck = openAIResponsesHealthCheck
        self.openAICompatibleHealthCheck = openAICompatibleHealthCheck
    }

    public func testConnection() async -> AppLLMProviderHealthCheckResult {
        do {
            let settings = try settingsRepository.loadSettings()
            let connection = settings.defaultConnection
            switch connection.providerMode {
            case .openAIResponses:
                guard let config = try settingsRepository.openAIResponsesConfig(connectionID: connection.id) else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "OpenAI Responses 连接缺少 API Key。")
                }
                let result = try await openAIResponsesHealthCheck(config)
                return AppLLMProviderHealthCheckResult(
                    status: result.ok ? .success : .failed,
                    message: result.message
                )
            case .anthropicMessages:
                guard try settingsRepository.anthropicCompatibleConfig(connectionID: connection.id) != nil else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "Anthropic Messages 连接缺少 API Key。")
                }
                return AppLLMProviderHealthCheckResult(status: .success, message: "Anthropic Messages 连接配置可用。")
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig(connectionID: connection.id) else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "OpenAI Compatible 连接缺少 API Key。")
                }
                let result = try await openAICompatibleHealthCheck(config)
                return AppLLMProviderHealthCheckResult(
                    status: result.ok ? .success : .failed,
                    message: result.message
                )
            }
        } catch {
            return AppLLMProviderHealthCheckResult(status: .failed, message: Self.safeMessage(for: error))
        }
    }

    private static func safeMessage(for error: Error) -> String {
        switch error {
        case OpenAICompatibleProviderError.missingAPIKey:
            return "OpenAI Compatible 连接缺少 API Key。"
        case let OpenAICompatibleProviderError.invalidBaseURL(value):
            return "Base URL 无效：\(value)"
        case OpenAICompatibleProviderError.invalidResponse:
            return "模型提供方返回了无效响应。"
        case let OpenAICompatibleProviderError.httpStatus(code, message):
            if let message, !message.isEmpty {
                return "模型提供方返回 HTTP 状态码 \(code)：\(message)"
            }
            return "模型提供方返回 HTTP 状态码 \(code)。"
        case OpenAICompatibleProviderError.missingAssistantMessage:
            return "模型提供方响应中没有助手消息。"
        default:
            return String(describing: error)
        }
    }
}
