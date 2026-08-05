import Foundation
import ConnorGraphAgent

public enum MemoryOSBackgroundFailureStrategy: String, Sendable, Equatable {
    /// Transient provider/network failure: requeue the same batch after a delay.
    case retry
    /// Deterministic batch-scope defect: re-plan the batch into smaller jobs before retrying.
    case downscale
    /// User action required (credentials, billing, configuration): hold with a long probe
    /// instead of hot-retrying, and surface the reason.
    case pause
}

public struct MemoryOSBackgroundFailureClassification: Sendable, Equatable {
    public var errorCode: String
    public var retryable: Bool
    public var retryDelay: TimeInterval?
    public var requiresUserAction: Bool
    public var strategy: MemoryOSBackgroundFailureStrategy

    public init(errorCode: String, retryable: Bool, retryDelay: TimeInterval? = nil, requiresUserAction: Bool = false, strategy: MemoryOSBackgroundFailureStrategy = .retry) {
        self.errorCode = errorCode
        self.retryable = retryable
        self.retryDelay = retryDelay
        self.requiresUserAction = requiresUserAction
        self.strategy = strategy
    }
}

public struct MemoryOSBackgroundFailureClassifier: Sendable {
    /// Error codes that mean the user must fix credentials, billing, or configuration before
    /// the batch can succeed. These are paused (long probe + attention) instead of hot-retried.
    public static let userActionErrorCodes: Set<String> = [
        "llm_billing_or_quota_exhausted",
        "llm_authentication_required",
        "llm_credentials_missing",
        "llm_provider_configuration_invalid",
        "llm_model_or_endpoint_not_found",
        "llm_provider_rejected_request"
    ]

    /// How often a paused (user-action) batch is probed again, and how long a downscaled
    /// batch waits before the next attempt.
    public static let pauseProbeInterval: TimeInterval = 6 * 3_600

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

        if let loopError = error as? MemoryOSHeadlessKnowledgeLoopError {
            switch loopError {
            case .exceededTokenBudget:
                // Deterministic batch-size mismatch: retrying the same oversized batch on a
                // short timer can never succeed. Re-plan into smaller batches instead.
                return downscale("background_ai_token_budget_exceeded")
            case .exceededMaxIterations:
                // Deterministic convergence failure for the current batch: re-plan smaller.
                return downscale("background_ai_max_iterations_exceeded")
            case .exceededMaxRunDuration:
                // The batch cannot finish within the duration cap at its current size.
                return downscale("background_ai_run_duration_exceeded")
            case .exceededMaxConsecutiveToolErrors:
                // The model keeps producing invalid tool calls for this batch: re-plan smaller.
                return downscale("background_ai_repeated_tool_errors")
            }
        }

        if let toolError = error as? MemoryOSBackgroundToolExecutionError {
            // Deterministic tool-call defects should not hot-retry the whole batch; give the
            // smaller re-planned batch a chance instead.
            return downscale("background_ai_tool_execution_failed")
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
        if status == 400 && containsContextLengthSignal(detail) {
            return downscale("background_ai_context_length_exceeded")
        }
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

    private func containsContextLengthSignal(_ value: String) -> Bool {
        ["context length", "context_length", "maximum context", "max context", "token limit", "too many tokens", "prompt is too long", "超出上下文", "上下文长度", "过长"].contains { value.contains($0) }
    }

    private func retry(_ code: String, after delay: TimeInterval) -> MemoryOSBackgroundFailureClassification {
        MemoryOSBackgroundFailureClassification(errorCode: code, retryable: true, retryDelay: delay, strategy: .retry)
    }

    private func userAction(_ code: String) -> MemoryOSBackgroundFailureClassification {
        MemoryOSBackgroundFailureClassification(errorCode: code, retryable: false, requiresUserAction: true, strategy: .pause)
    }

    private func downscale(_ code: String) -> MemoryOSBackgroundFailureClassification {
        MemoryOSBackgroundFailureClassification(errorCode: code, retryable: false, strategy: .downscale)
    }
}
