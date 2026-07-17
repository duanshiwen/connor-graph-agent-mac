import Foundation
import ConnorGraphAgent

public struct MemoryOSBackgroundFailureClassification: Sendable, Equatable {
    public var errorCode: String
    public var retryable: Bool
    public var retryDelay: TimeInterval?
    public var requiresUserAction: Bool

    public init(errorCode: String, retryable: Bool, retryDelay: TimeInterval? = nil, requiresUserAction: Bool = false) {
        self.errorCode = errorCode
        self.retryable = retryable
        self.retryDelay = retryDelay
        self.requiresUserAction = requiresUserAction
    }
}

public struct MemoryOSBackgroundFailureClassifier: Sendable {
    public init() {}

    public func classify(_ error: Error) -> MemoryOSBackgroundFailureClassification {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return userAction("llm_authentication_required")
            default:
                return retry("llm_network_unavailable", after: 30)
            }
        }

        if let providerError = error as? OpenAICompatibleProviderError {
            switch providerError {
            case let .httpStatus(status, message): return classifyHTTP(status: status, message: message)
            case .missingAPIKey: return userAction("llm_credentials_missing")
            case .invalidBaseURL: return userAction("llm_provider_configuration_invalid")
            default: break
            }
        }
        if let providerError = error as? AnthropicCompatibleProviderError {
            if case let .httpStatus(status, message) = providerError {
                return classifyHTTP(status: status, message: message)
            }
        }

        let description = [String(describing: error), (error as NSError).localizedDescription]
            .joined(separator: " ")
            .lowercased()
        if containsBillingSignal(description) { return userAction("llm_billing_or_quota_exhausted") }
        if description.contains("api key") || description.contains("unauthorized") || description.contains("authentication") {
            return userAction("llm_authentication_required")
        }
        if description.contains("timed out") || description.contains("network") || description.contains("connection") {
            return retry("llm_network_unavailable", after: 30)
        }
        return retry("background_ai_job_failed", after: 15)
    }

    private func classifyHTTP(status: Int, message: String?) -> MemoryOSBackgroundFailureClassification {
        let detail = (message ?? "").lowercased()
        if status == 402 || containsBillingSignal(detail) { return userAction("llm_billing_or_quota_exhausted") }
        switch status {
        case 401, 403: return userAction("llm_authentication_required")
        case 404: return userAction("llm_model_or_endpoint_not_found")
        case 408: return retry("llm_request_timeout", after: 30)
        case 409: return retry("llm_provider_conflict", after: 30)
        case 429: return retry("llm_rate_limited", after: 60)
        case 500...599: return retry("llm_provider_unavailable", after: 30)
        default: return userAction("llm_provider_rejected_request")
        }
    }

    private func containsBillingSignal(_ value: String) -> Bool {
        ["insufficient_quota", "quota exceeded", "billing", "credit balance", "payment required", "余额", "额度", "欠费"].contains { value.contains($0) }
    }

    private func retry(_ code: String, after delay: TimeInterval) -> MemoryOSBackgroundFailureClassification {
        MemoryOSBackgroundFailureClassification(errorCode: code, retryable: true, retryDelay: delay)
    }

    private func userAction(_ code: String) -> MemoryOSBackgroundFailureClassification {
        MemoryOSBackgroundFailureClassification(errorCode: code, retryable: false, requiresUserAction: true)
    }
}
