import Foundation
import ConnorGraphCore

public struct GraphExtractionPromptBuilder: Sendable {
    public static let defaultPromptVersion = "graph-extraction-v1"

    public var allowedPredicates: [GraphPredicate]
    public var allowedEntityKinds: [GraphEntityKind]
    public var allowedScopes: [GraphScope]
    public var requireEvidence: Bool

    public init(
        allowedPredicates: [GraphPredicate] = GraphPredicate.allCases,
        allowedEntityKinds: [GraphEntityKind] = GraphEntityKind.allCases,
        allowedScopes: [GraphScope] = GraphScope.allCases,
        requireEvidence: Bool = true
    ) {
        self.allowedPredicates = allowedPredicates
        self.allowedEntityKinds = allowedEntityKinds
        self.allowedScopes = allowedScopes
        self.requireEvidence = requireEvidence
    }

    public func buildPrompt(for source: GraphExtractionSource) -> String {
        let predicateList = allowedPredicates.map(\.rawValue).sorted().joined(separator: ", ")
        let entityKindList = allowedEntityKinds.map(\.rawValue).sorted().joined(separator: ", ")
        let scopeList = allowedScopes.map(\.rawValue).sorted().joined(separator: ", ")
        let metadataText = source.metadata
            .sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")

        return """
        You are a production graph extraction engine for a local-first AI agent.

        Extract only evidence-backed candidate graph memory from the source below.
        You produce extraction drafts only. You do not commit facts to the graph truth layer.

        Hard rules:
        - Output JSON only. Do not wrap the JSON in Markdown unless the caller explicitly asks for markdown.
        - Do not invent facts that are not supported by the source.
        - Every statement must reference subjectLocalID and objectLocalID from the entities array.
        - Every statement must use one allowed predicate.
        - Every entity must use one allowed entityKind and one allowed scope.
        - Prefer fewer, high-confidence entities/statements over noisy extraction.
        - Capture uncertainty as warnings instead of forcing low-quality facts.
        \(requireEvidence ? "- Every statement must include at least one evidenceSpanID." : "- Evidence spans are recommended for every statement.")

        Allowed predicates:
        \(predicateList)

        Allowed entity kinds:
        \(entityKindList)

        Allowed scopes:
        \(scopeList)

        Required JSON shape:
        {
          "entities": [
            {
              "localID": "stable-local-id",
              "name": "display name",
              "entityKind": "one allowed entity kind",
              "scope": "one allowed scope",
              "canonicalClassID": null,
              "aliases": [],
              "summary": "short evidence-backed summary",
              "confidence": 0.0,
              "evidenceSpanIDs": ["span-1"],
              "metadata": {}
            }
          ],
          "statements": [
            {
              "explicitID": null,
              "subjectLocalID": "entity-local-id",
              "predicate": "ALLOWED_PREDICATE",
              "objectLocalID": "entity-local-id",
              "statementText": "human readable fact",
              "confidence": 0.0,
              "validAt": null,
              "referenceTime": null,
              "evidenceSpanIDs": ["span-1"],
              "metadata": {}
            }
          ],
          "evidenceSpans": [
            {
              "id": "span-1",
              "text": "exact quote from source",
              "startOffset": null,
              "endOffset": null
            }
          ],
          "warnings": [],
          "confidence": null,
          "metadata": {}
        }

        Source metadata:
        - source_id: \(source.id)
        - graph_id: \(source.graphID)
        - source_type: \(source.sourceType.rawValue)
        - title: \(source.title)
        - occurred_at: \(ISO8601DateFormatter().string(from: source.occurredAt))
        \(source.sessionID.map { "- session_id: \($0)" } ?? "")
        \(source.workObjectID.map { "- work_object_id: \($0)" } ?? "")
        \(metadataText.isEmpty ? "" : metadataText)

        Source content:
        ```text
        \(source.content)
        ```
        """
    }
}
