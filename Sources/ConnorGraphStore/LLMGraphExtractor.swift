import Foundation
import ConnorGraphCore

public struct GraphExtractionLLMResponse: Sendable, Equatable {
    public var text: String
    public var provider: String?
    public var modelID: String?
    public var promptVersion: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var latencyMilliseconds: Int?
    public var rawResponseID: String?
    public var rawResponseJSON: String?
    public var estimatedCostUSD: Decimal?
    public var metadata: [String: String]

    public init(
        text: String,
        provider: String? = nil,
        modelID: String? = nil,
        promptVersion: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        latencyMilliseconds: Int? = nil,
        rawResponseID: String? = nil,
        rawResponseJSON: String? = nil,
        estimatedCostUSD: Decimal? = nil,
        metadata: [String: String] = [:]
    ) {
        self.text = text
        self.provider = provider
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.latencyMilliseconds = latencyMilliseconds
        self.rawResponseID = rawResponseID
        self.rawResponseJSON = rawResponseJSON
        self.estimatedCostUSD = estimatedCostUSD
        self.metadata = metadata
    }

    public var traceMetadata: [String: String] {
        var values = metadata
        values["llm_provider"] = provider
        values["llm_model_id"] = modelID
        values["prompt_version"] = promptVersion
        values["prompt_tokens"] = promptTokens.map(String.init)
        values["completion_tokens"] = completionTokens.map(String.init)
        values["total_tokens"] = totalTokens.map(String.init)
        values["latency_ms"] = latencyMilliseconds.map(String.init)
        values["raw_response_id"] = rawResponseID
        values["raw_response_json"] = rawResponseJSON
        values["estimated_cost_usd"] = estimatedCostUSD.map { NSDecimalNumber(decimal: $0).stringValue }
        return values
    }
}

public protocol GraphExtractionLLMClient: Sendable {
    func completeExtraction(prompt: String) async throws -> GraphExtractionLLMResponse
}

public struct GraphExtractionAttemptFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public var source: GraphExtractionSource
    public var response: GraphExtractionLLMResponse
    public var normalizedJSON: String?
    public var decoderWarnings: [String]
    public var underlyingDescription: String
    public var decoderErrorKind: String

    public init(
        source: GraphExtractionSource,
        response: GraphExtractionLLMResponse,
        normalizedJSON: String? = nil,
        decoderWarnings: [String] = [],
        underlyingDescription: String,
        decoderErrorKind: String
    ) {
        self.source = source
        self.response = response
        self.normalizedJSON = normalizedJSON
        self.decoderWarnings = decoderWarnings
        self.underlyingDescription = underlyingDescription
        self.decoderErrorKind = decoderErrorKind
    }

    public var description: String {
        "graphExtractionAttemptFailure(\(decoderErrorKind)): \(underlyingDescription)"
    }

    public var traceMetadata: [String: String] {
        var metadata = response.traceMetadata
        metadata["decoder_error_kind"] = decoderErrorKind
        metadata["decoder_error_message"] = underlyingDescription
        metadata["normalized_json"] = normalizedJSON
        if !decoderWarnings.isEmpty {
            metadata["decoder_warnings"] = decoderWarnings.joined(separator: ",")
        }
        return metadata
    }
}

public struct LLMGraphExtractor<Client: GraphExtractionLLMClient>: GraphExtractorProvider, Sendable {
    public var client: Client
    public var promptBuilder: GraphExtractionPromptBuilder
    public var decoder: GraphExtractionDecoder

    public init(
        client: Client,
        promptBuilder: GraphExtractionPromptBuilder = GraphExtractionPromptBuilder(),
        decoder: GraphExtractionDecoder = GraphExtractionDecoder()
    ) {
        self.client = client
        self.promptBuilder = promptBuilder
        self.decoder = decoder
    }

    public func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        let prompt = promptBuilder.buildPrompt(for: source)
        let response = try await client.completeExtraction(prompt: prompt)
        let decoded: GraphExtractionDecodingResult
        do {
            decoded = try decoder.decode(response.text)
        } catch {
            let candidate = decoder.normalizedJSONCandidate(from: response.text)
            var failureResponse = response
            failureResponse.metadata["prompt_text"] = prompt
            throw GraphExtractionAttemptFailure(
                source: source,
                response: failureResponse,
                normalizedJSON: candidate?.json,
                decoderWarnings: candidate?.warnings ?? [],
                underlyingDescription: String(describing: error),
                decoderErrorKind: Self.decoderErrorKind(error)
            )
        }
        var draft = try decoded.output.toDraft(source: source, requireStatementEvidence: decoder.requireStatementEvidence)
        var metadata = response.traceMetadata
        metadata["prompt_text"] = prompt
        metadata["normalized_json"] = decoded.normalizedJSON
        if !decoded.warnings.isEmpty {
            metadata["decoder_warnings"] = decoded.warnings.joined(separator: ",")
        }
        draft.metadata = metadata
        return draft
    }

    private static func decoderErrorKind(_ error: Error) -> String {
        guard let decodingError = error as? GraphExtractionDecodingError else {
            return "unknown"
        }
        switch decodingError {
        case .emptyResponse: return "empty_response"
        case .invalidJSON: return "invalid_json"
        case .schemaViolation: return "schema_violation"
        }
    }
}

public struct ClosureGraphExtractionLLMClient: GraphExtractionLLMClient, Sendable {
    public var completion: @Sendable (String) async throws -> GraphExtractionLLMResponse

    public init(completion: @escaping @Sendable (String) async throws -> GraphExtractionLLMResponse) {
        self.completion = completion
    }

    public init(textCompletion: @escaping @Sendable (String) async throws -> String) {
        self.completion = { prompt in GraphExtractionLLMResponse(text: try await textCompletion(prompt)) }
    }

    public func completeExtraction(prompt: String) async throws -> GraphExtractionLLMResponse {
        try await completion(prompt)
    }
}
