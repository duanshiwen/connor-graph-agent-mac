import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Coarse classification of model provider failures used by the agent loop to
/// decide between context recovery, transient retry, and permanent failure.
public enum AgentModelProviderErrorClass: String, Sendable, Equatable {
    case contextOverflow
    case transient
    case permanent
}

/// Providers conform their typed errors to this protocol so the agent loop can
/// classify failures without matching on error description strings.
public protocol AgentModelProviderErrorClassifying {
    var providerErrorClass: AgentModelProviderErrorClass { get }
}

enum AgentProviderErrorHeuristics {
    static let contextOverflowMessageFragments: [String] = [
        "exceeds the context window",
        "context window exceeded",
        "context length exceeded",
        "maximum context length",
        "model_context_window_exceeded",
        "too many input tokens"
    ]

    static func isContextOverflowMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let lowered = message.lowercased()
        return contextOverflowMessageFragments.contains { lowered.contains($0) }
    }

    static func classifyHTTPStatus(_ status: Int, message: String?) -> AgentModelProviderErrorClass {
        if isContextOverflowMessage(message) { return .contextOverflow }
        switch status {
        case 408, 409, 425, 429, 500...599:
            return .transient
        default:
            return .permanent
        }
    }
}

extension AnthropicCompatibleProviderError: AgentModelProviderErrorClassifying {
    public var providerErrorClass: AgentModelProviderErrorClass {
        switch self {
        case .invalidResponse:
            return .transient
        case let .httpStatus(status, message):
            return AgentProviderErrorHeuristics.classifyHTTPStatus(status, message: message)
        case let .streamError(message):
            return AgentProviderErrorHeuristics.isContextOverflowMessage(message) ? .contextOverflow : .transient
        case .missingAssistantMessage, .unsupportedVisionInput, .invalidImageDataURL:
            return .permanent
        }
    }
}

extension OpenAICompatibleProviderError: AgentModelProviderErrorClassifying {
    public var providerErrorClass: AgentModelProviderErrorClass {
        switch self {
        case .invalidResponse:
            return .transient
        case let .httpStatus(status, message):
            return AgentProviderErrorHeuristics.classifyHTTPStatus(status, message: message)
        case .missingAPIKey, .invalidBaseURL, .missingAssistantMessage, .unsupportedVisionInput:
            return .permanent
        }
    }
}
