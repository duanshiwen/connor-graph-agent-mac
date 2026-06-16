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
    public var openAICompatibleHealthCheck: OpenAICompatibleHealthCheck

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        openAICompatibleHealthCheck: @escaping OpenAICompatibleHealthCheck = { config in
            try await OpenAICompatibleProvider(config: config).healthCheck()
        }
    ) {
        self.settingsRepository = settingsRepository
        self.openAICompatibleHealthCheck = openAICompatibleHealthCheck
    }

    public func testConnection() async -> AppLLMProviderHealthCheckResult {
        do {
            let settings = try settingsRepository.loadSettings()
            let connection = settings.defaultConnection
            switch connection.providerMode {
            case .governedClaudeSidecar:
                let path = connection.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "Claude 连接缺少 sidecar executable path。")
                }
                guard connection.sidecarPermissionMode != .allowAll else {
                    return AppLLMProviderHealthCheckResult(status: .failed, message: "Claude 连接不允许 allowAll 权限模式。")
                }
                return AppLLMProviderHealthCheckResult(status: .success, message: "Claude 连接配置可用；实际 SDK 登录和依赖由 sidecar 运行时验证。")
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
        case let OpenAICompatibleProviderError.httpStatus(code):
            return "模型提供方返回 HTTP 状态码 \(code)。"
        case OpenAICompatibleProviderError.missingAssistantMessage:
            return "模型提供方响应中没有助手消息。"
        default:
            return String(describing: error)
        }
    }
}
