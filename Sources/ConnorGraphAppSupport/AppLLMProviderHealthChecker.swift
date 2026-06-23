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
            return AppLLMProviderHealthCheckResult(status: .failed, message: Self.userFacingMessage(for: error))
        }
    }

    public static func userFacingMessage(for error: Error) -> String {
        switch error {
        case OpenAICompatibleProviderError.missingAPIKey:
            return "OpenAI Compatible 连接缺少 API Key。"
        case let OpenAICompatibleProviderError.invalidBaseURL(value):
            return "Base URL 无效：\(value)"
        case OpenAICompatibleProviderError.invalidResponse:
            return "模型提供方返回了无效响应。"
        case let OpenAICompatibleProviderError.httpStatus(code, message):
            return userFacingHTTPStatusMessage(code: code, message: message)
        case OpenAICompatibleProviderError.missingAssistantMessage:
            return "模型提供方响应中没有助手消息。"
        case AnthropicCompatibleProviderError.invalidResponse:
            return "Anthropic Messages 提供方返回了无效响应。"
        case let AnthropicCompatibleProviderError.httpStatus(code, message):
            return userFacingHTTPStatusMessage(code: code, message: message)
        case AnthropicCompatibleProviderError.missingAssistantMessage:
            return "Anthropic Messages 响应中没有助手消息。"
        case let AnthropicCompatibleProviderError.streamError(message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Anthropic Messages 流式响应出错。" : message
        default:
            if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                return localized
            }
            return String(describing: error)
        }
    }

    private static func userFacingHTTPStatusMessage(code: Int, message: String?) -> String {
        let suffix = message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch code {
        case 400:
            return suffix.map { "请求参数不被服务端接受（HTTP 400）：\($0)" } ?? "请求参数不被服务端接受（HTTP 400）。请检查模型 ID、Endpoint 与兼容模式。"
        case 401, 403:
            return suffix.map { "API Key 无效或没有权限（HTTP \(code)）：\($0)" } ?? "API Key 无效或没有权限（HTTP \(code)）。请检查密钥和服务商权限。"
        case 503:
            return suffix.map { "服务暂时不可用（HTTP 503）：\($0)。可能是模型服务过载、维护、上游网关不可达，或兼容模式选择不匹配。" } ?? "服务暂时不可用（HTTP 503）。可能是模型服务过载、维护、上游网关不可达，或兼容模式选择不匹配。请确认兼容模式与服务端接口一致后稍后重试。"
        default:
            return suffix.map { "模型服务返回 HTTP \(code)：\($0)" } ?? "模型服务返回 HTTP \(code)。"
        }
    }
}
