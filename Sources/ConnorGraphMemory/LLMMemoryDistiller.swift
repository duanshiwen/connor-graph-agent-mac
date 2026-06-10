import Foundation

public struct MemoryDistillationLLMResponse: Sendable, Equatable {
    public var text: String
    public var provider: String?
    public var modelID: String?
    public var promptVersion: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var latencyMilliseconds: Int?
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
        return values
    }
}

public protocol MemoryDistillationLLMClient: Sendable {
    func completeDistillation(prompt: String) async throws -> MemoryDistillationLLMResponse
}

public struct MemoryDistillationPromptBuilder: Sendable {
    public static let defaultPromptVersion = "memory-distillation-llm-v1"
    public var promptVersion: String
    public var deterministicRenderer: MemoryDistillationService

    public init(
        promptVersion: String = Self.defaultPromptVersion,
        deterministicRenderer: MemoryDistillationService = MemoryDistillationService()
    ) {
        self.promptVersion = promptVersion
        self.deterministicRenderer = deterministicRenderer
    }

    public func buildPrompt(buffer: MemoryStagingBuffer) -> String {
        let closedBundles = buffer.pendingBundles.filter { $0.status == .closed }
        let renderedBundles = closedBundles.enumerated().map { index, bundle in
            """
            Bundle \(index + 1)
            bundle_id: \(bundle.id)
            session_id: \(bundle.sessionID)
            content:
            \(deterministicRenderer.renderBundle(bundle))
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        You are a memory distillation engine for a local-first AI Agent.

        Task:
        - Read closed conversation turn bundles.
        - Select only durable, useful long-term memory candidates.
        - Classify each candidate as one of:
          episode, profile_fact, decision, project_fact, preference, unresolved_question, risk_flag.
        - Reject low-value chit-chat, acknowledgements, duplicated or unclear content.
        - Do not invent facts. Preserve evidence in source_bundle_id and source_message_ids when possible.

        Return ONLY valid JSON with this exact shape:
        {
          "candidates": [
            {
              "kind": "preference",
              "title": "Short title",
              "content": "Evidence-grounded memory content",
              "rationale": "Why this should be remembered",
              "importance": 0.0,
              "confidence": 0.0,
              "source_bundle_id": "bundle-id",
              "source_message_ids": ["message-id"],
              "metadata": {"key": "value"}
            }
          ],
          "discarded_items": [
            {
              "source_bundle_id": "bundle-id",
              "reason": "low_value_or_unclear",
              "summary": "Short summary"
            }
          ]
        }

        Constraints:
        - importance and confidence must be numbers between 0 and 1.
        - Use source_bundle_id exactly as provided.
        - If nothing is worth remembering, return {"candidates": [], "discarded_items": [...]}.

        Input bundles:
        \(renderedBundles.isEmpty ? "No closed bundles." : renderedBundles)
        """
    }
}

public enum MemoryDistillationDecodingError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyResponse
    case invalidJSON
    case schemaViolation(String)

    public var description: String {
        switch self {
        case .emptyResponse: "empty_response"
        case .invalidJSON: "invalid_json"
        case .schemaViolation(let message): "schema_violation: \(message)"
        }
    }
}

public struct MemoryDistillationDecoder: Sendable {
    public var qualityGatePolicy: MemoryDistillationQualityGatePolicy

    public init(qualityGatePolicy: MemoryDistillationQualityGatePolicy = MemoryDistillationQualityGatePolicy()) {
        self.qualityGatePolicy = qualityGatePolicy
    }

    public func decode(_ text: String, buffer: MemoryStagingBuffer, fallbackResultID: String = UUID().uuidString, createdAt: Date = Date()) throws -> MemoryDistillationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryDistillationDecodingError.emptyResponse }
        guard let json = normalizedJSONCandidate(from: trimmed), let data = json.data(using: .utf8) else {
            throw MemoryDistillationDecodingError.invalidJSON
        }
        let output = try JSONDecoder().decode(LLMMemoryDistillationOutput.self, from: data)
        return try output.toResult(
            id: fallbackResultID,
            buffer: buffer,
            createdAt: createdAt,
            qualityGatePolicy: qualityGatePolicy,
            normalizedJSON: json
        )
    }

    public func normalizedJSONCandidate(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return trimmed }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end else { return nil }
        return String(trimmed[start...end])
    }
}

private struct LLMMemoryDistillationOutput: Decodable {
    var candidates: [LLMMemoryCandidate]
    var discardedItems: [LLMDiscardedItem]

    enum CodingKeys: String, CodingKey {
        case candidates
        case discardedItems = "discarded_items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidates = try container.decodeIfPresent([LLMMemoryCandidate].self, forKey: .candidates) ?? []
        self.discardedItems = try container.decodeIfPresent([LLMDiscardedItem].self, forKey: .discardedItems) ?? []
    }

    func toResult(
        id: String,
        buffer: MemoryStagingBuffer,
        createdAt: Date,
        qualityGatePolicy: MemoryDistillationQualityGatePolicy,
        normalizedJSON: String
    ) throws -> MemoryDistillationResult {
        let closedBundlesByID = Dictionary(uniqueKeysWithValues: buffer.pendingBundles.filter { $0.status == .closed }.map { ($0.id, $0) })
        let sourceRefs = closedBundlesByID.values.map { bundle in
            MemoryDistillationSourceRef(
                bundleID: bundle.id,
                messageIDs: bundle.userMessages.map(\.id) + (bundle.assistantMessage.map { [$0.id] } ?? []),
                artifactIDs: bundle.artifacts.map(\.id),
                quote: MemoryDistillationService().renderBundle(bundle),
                metadata: ["session_id": bundle.sessionID]
            )
        }
        let sourceRefByBundleID = Dictionary(uniqueKeysWithValues: sourceRefs.map { ($0.bundleID, $0) })
        var result = MemoryDistillationResult(
            id: id,
            sessionID: buffer.sessionID,
            sourceBufferID: buffer.id,
            sourceRefs: sourceRefs,
            trace: MemoryDistillationTrace(
                model: "llm",
                promptVersion: MemoryDistillationPromptBuilder.defaultPromptVersion,
                inputBundleCount: closedBundlesByID.count,
                metadata: ["normalized_json": normalizedJSON]
            ),
            createdAt: createdAt
        )

        for candidate in candidates {
            guard closedBundlesByID[candidate.sourceBundleID] != nil else {
                throw MemoryDistillationDecodingError.schemaViolation("unknown source_bundle_id: \(candidate.sourceBundleID)")
            }
            guard let kind = MemoryDistillationCandidateKind(rawValue: candidate.kind) else {
                throw MemoryDistillationDecodingError.schemaViolation("unknown candidate kind: \(candidate.kind)")
            }
            let distilled = MemoryDistillationCandidate(
                kind: kind,
                title: candidate.title,
                content: candidate.content,
                rationale: candidate.rationale,
                importance: min(max(candidate.importance, 0), 1),
                confidence: min(max(candidate.confidence, 0), 1),
                sourceRefIDs: sourceRefByBundleID[candidate.sourceBundleID].map { [$0.id] } ?? [],
                status: .proposed,
                metadata: candidate.metadata.merging([
                    "bundle_id": candidate.sourceBundleID,
                    "session_id": buffer.sessionID,
                    "candidate_origin": "llm_memory_distiller",
                    "classification_method": "llm"
                ]) { current, _ in current }
            )
            guard passesQualityGate(distilled, policy: qualityGatePolicy) else {
                result.discardedItems.append(MemoryDistillationDiscardedItem(
                    bundleID: candidate.sourceBundleID,
                    reason: "quality_gate_rejected",
                    summary: candidate.title
                ))
                continue
            }
            result.append(candidate: distilled)
        }

        result.discardedItems.append(contentsOf: discardedItems.map {
            MemoryDistillationDiscardedItem(bundleID: $0.sourceBundleID, reason: $0.reason, summary: $0.summary)
        })
        return result
    }

    private func passesQualityGate(_ candidate: MemoryDistillationCandidate, policy: MemoryDistillationQualityGatePolicy) -> Bool {
        candidate.content.trimmingCharacters(in: .whitespacesAndNewlines).count >= policy.minimumContentCharacters
            && candidate.importance >= policy.minimumImportance
            && candidate.confidence >= policy.minimumConfidence
    }
}

private struct LLMMemoryCandidate: Decodable {
    var kind: String
    var title: String
    var content: String
    var rationale: String
    var importance: Double
    var confidence: Double
    var sourceBundleID: String
    var sourceMessageIDs: [String]
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case kind, title, content, rationale, importance, confidence, metadata
        case sourceBundleID = "source_bundle_id"
        case sourceMessageIDs = "source_message_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.content = try container.decode(String.self, forKey: .content)
        self.rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        self.importance = try container.decodeIfPresent(Double.self, forKey: .importance) ?? 0.5
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        self.sourceBundleID = try container.decode(String.self, forKey: .sourceBundleID)
        self.sourceMessageIDs = try container.decodeIfPresent([String].self, forKey: .sourceMessageIDs) ?? []
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

private struct LLMDiscardedItem: Decodable {
    var sourceBundleID: String
    var reason: String
    var summary: String

    enum CodingKeys: String, CodingKey {
        case reason, summary
        case sourceBundleID = "source_bundle_id"
    }
}

public struct ClosureMemoryDistillationLLMClient: MemoryDistillationLLMClient, Sendable {
    public var completion: @Sendable (String) async throws -> MemoryDistillationLLMResponse

    public init(completion: @escaping @Sendable (String) async throws -> MemoryDistillationLLMResponse) {
        self.completion = completion
    }

    public init(textCompletion: @escaping @Sendable (String) async throws -> String) {
        self.completion = { prompt in MemoryDistillationLLMResponse(text: try await textCompletion(prompt)) }
    }

    public func completeDistillation(prompt: String) async throws -> MemoryDistillationLLMResponse {
        try await completion(prompt)
    }
}

public struct LLMMemoryDistiller<Client: MemoryDistillationLLMClient>: Sendable {
    public var client: Client
    public var promptBuilder: MemoryDistillationPromptBuilder
    public var decoder: MemoryDistillationDecoder
    public var fallback: MemoryDistillationService

    public init(
        client: Client,
        promptBuilder: MemoryDistillationPromptBuilder = MemoryDistillationPromptBuilder(),
        decoder: MemoryDistillationDecoder = MemoryDistillationDecoder(),
        fallback: MemoryDistillationService = MemoryDistillationService()
    ) {
        self.client = client
        self.promptBuilder = promptBuilder
        self.decoder = decoder
        self.fallback = fallback
    }

    public func distill(buffer: MemoryStagingBuffer, at date: Date = Date(), triggerReasons: [MemoryStagingTriggerReason]? = nil) async -> MemoryDistillationResult {
        let prompt = promptBuilder.buildPrompt(buffer: buffer)
        do {
            let response = try await client.completeDistillation(prompt: prompt)
            var result = try decoder.decode(response.text, buffer: buffer, createdAt: date)
            result.trace.model = response.modelID ?? "llm"
            result.trace.promptVersion = response.promptVersion ?? promptBuilder.promptVersion
            result.trace.triggerReasons = triggerReasons ?? buffer.triggerReasons(at: date)
            var metadata = result.trace.metadata
            metadata.merge(response.traceMetadata) { current, _ in current }
            metadata["distiller"] = "llm"
            metadata["prompt_text"] = prompt
            result.trace.metadata = metadata
            return result
        } catch {
            var result = fallback.distill(buffer: buffer, at: date, triggerReasons: triggerReasons)
            var metadata = result.trace.metadata
            metadata["distiller"] = "deterministic_fallback"
            metadata["llm_distiller_error"] = String(describing: error)
            metadata["prompt_text"] = prompt
            result.trace.metadata = metadata
            return result
        }
    }
}

private extension MemoryDistillationResult {
    mutating func append(candidate: MemoryDistillationCandidate) {
        switch candidate.kind {
        case .episode:
            episodeCandidates.append(candidate)
        case .profileFact:
            profileFactCandidates.append(candidate)
        case .decision:
            decisionCandidates.append(candidate)
        case .projectFact:
            projectFactCandidates.append(candidate)
        case .preference:
            preferenceCandidates.append(candidate)
        case .unresolvedQuestion:
            unresolvedQuestions.append(candidate)
        case .riskFlag:
            riskFlags.append(candidate)
        }
    }
}
