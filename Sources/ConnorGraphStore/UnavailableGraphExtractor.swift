import Foundation
import ConnorGraphCore

public enum UnavailableGraphExtractorError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingLLMConfiguration
    case invalidLLMConfiguration(String)

    public var description: String {
        switch self {
        case .missingLLMConfiguration:
            return "Graph extraction requires a configured OpenAI-compatible LLM provider."
        case .invalidLLMConfiguration(let message):
            return "Graph extraction LLM configuration is invalid: \(message)"
        }
    }
}

/// Explicit failure extractor used when graph extraction is requested before a
/// production LLM-backed extractor can be constructed. This keeps background
/// jobs honest: extraction jobs fail with a diagnosable reason instead of
/// silently committing empty drafts.
public struct UnavailableGraphExtractor: GraphExtractorProvider, Sendable, Equatable {
    public var error: UnavailableGraphExtractorError

    public init(error: UnavailableGraphExtractorError = .missingLLMConfiguration) {
        self.error = error
    }

    public func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        throw error
    }
}
