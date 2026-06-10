import Foundation

public struct MemoryDistillationService: Sendable {
    public var modelName: String
    public var promptVersion: String

    public init(modelName: String = "deterministic-memory-distiller", promptVersion: String = "memory-distillation-v0") {
        self.modelName = modelName
        self.promptVersion = promptVersion
    }

    public func distill(
        buffer: MemoryStagingBuffer,
        at date: Date = Date(),
        triggerReasons: [MemoryStagingTriggerReason]? = nil
    ) -> MemoryDistillationResult {
        let closedBundles = buffer.pendingBundles.filter { $0.status == .closed }
        let sourceRefs = closedBundles.map { sourceRef(for: $0) }
        let sourceRefByBundleID = Dictionary(uniqueKeysWithValues: sourceRefs.map { ($0.bundleID, $0) })
        let episodeCandidates = closedBundles.map { bundle in
            episodeCandidate(for: bundle, sourceRef: sourceRefByBundleID[bundle.id])
        }
        let discardedItems = buffer.pendingBundles
            .filter { $0.status != .closed }
            .map { bundle in
                MemoryDistillationDiscardedItem(
                    bundleID: bundle.id,
                    reason: "bundle_not_closed",
                    summary: bundle.userMessages.first?.content ?? bundle.artifacts.first?.summary ?? ""
                )
            }
        let reasons = triggerReasons ?? buffer.triggerReasons(at: date)
        let inputText = closedBundles.map { renderBundle($0) }.joined(separator: "\n\n")
        let trace = MemoryDistillationTrace(
            model: modelName,
            promptVersion: promptVersion,
            inputBundleCount: closedBundles.count,
            inputTokenEstimate: estimateTokens(inputText),
            outputTokenEstimate: estimateTokens(episodeCandidates.map(\.content).joined(separator: "\n\n")),
            triggerReasons: reasons,
            createdAt: date,
            metadata: ["distiller": "deterministic"]
        )
        return MemoryDistillationResult(
            sessionID: buffer.sessionID,
            sourceBufferID: buffer.id,
            episodeCandidates: episodeCandidates,
            discardedItems: discardedItems,
            sourceRefs: sourceRefs,
            trace: trace,
            createdAt: date
        )
    }

    public func renderBundle(_ bundle: ConversationTurnBundle) -> String {
        var lines: [String] = []
        for message in bundle.userMessages {
            lines.append("User: \(message.content)")
        }
        if let assistantMessage = bundle.assistantMessage {
            lines.append("Assistant: \(assistantMessage.content)")
        }
        for artifact in bundle.artifacts {
            let summary = artifact.summary.isEmpty ? artifact.content : artifact.summary
            lines.append("Artifact[\(artifact.kind.rawValue)]: \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    private func sourceRef(for bundle: ConversationTurnBundle) -> MemoryDistillationSourceRef {
        MemoryDistillationSourceRef(
            bundleID: bundle.id,
            messageIDs: bundle.userMessages.map(\.id) + (bundle.assistantMessage.map { [$0.id] } ?? []),
            artifactIDs: bundle.artifacts.map(\.id),
            quote: renderBundle(bundle),
            metadata: ["session_id": bundle.sessionID]
        )
    }

    private func episodeCandidate(for bundle: ConversationTurnBundle, sourceRef: MemoryDistillationSourceRef?) -> MemoryDistillationCandidate {
        let firstUserMessage = bundle.userMessages.first?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Conversation turn"
        let title = String(firstUserMessage.prefix(80))
        return MemoryDistillationCandidate(
            kind: .episode,
            title: title.isEmpty ? "Conversation turn" : title,
            content: renderBundle(bundle),
            rationale: "Closed conversation turn is ready for graph extraction.",
            importance: 0.5,
            confidence: 0.8,
            sourceRefIDs: sourceRef.map { [$0.id] } ?? [],
            status: .proposed,
            metadata: [
                "bundle_id": bundle.id,
                "session_id": bundle.sessionID,
                "candidate_origin": "memory_staging_buffer"
            ]
        )
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
