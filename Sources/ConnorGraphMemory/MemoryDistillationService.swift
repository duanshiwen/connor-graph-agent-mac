import Foundation

public struct MemoryDistillationQualityGatePolicy: Codable, Sendable, Equatable {
    public var minimumContentCharacters: Int
    public var minimumImportance: Double
    public var minimumConfidence: Double

    public init(
        minimumContentCharacters: Int = 12,
        minimumImportance: Double = 0.4,
        minimumConfidence: Double = 0.5
    ) {
        self.minimumContentCharacters = minimumContentCharacters
        self.minimumImportance = minimumImportance
        self.minimumConfidence = minimumConfidence
    }
}

public struct MemoryDistillationService: Sendable {
    public var modelName: String
    public var promptVersion: String
    public var qualityGatePolicy: MemoryDistillationQualityGatePolicy

    public init(
        modelName: String = "deterministic-memory-distiller",
        promptVersion: String = "memory-distillation-v1",
        qualityGatePolicy: MemoryDistillationQualityGatePolicy = MemoryDistillationQualityGatePolicy()
    ) {
        self.modelName = modelName
        self.promptVersion = promptVersion
        self.qualityGatePolicy = qualityGatePolicy
    }

    public func distill(
        buffer: MemoryStagingBuffer,
        at date: Date = Date(),
        triggerReasons: [MemoryStagingTriggerReason]? = nil
    ) -> MemoryDistillationResult {
        let closedBundles = buffer.pendingBundles.filter { $0.status == .closed }
        let sourceRefs = closedBundles.map { sourceRef(for: $0) }
        let sourceRefByBundleID = Dictionary(uniqueKeysWithValues: sourceRefs.map { ($0.bundleID, $0) })
        var episodeCandidates: [MemoryDistillationCandidate] = []
        var profileFactCandidates: [MemoryDistillationCandidate] = []
        var decisionCandidates: [MemoryDistillationCandidate] = []
        var projectFactCandidates: [MemoryDistillationCandidate] = []
        var preferenceCandidates: [MemoryDistillationCandidate] = []
        var unresolvedQuestions: [MemoryDistillationCandidate] = []
        var riskFlags: [MemoryDistillationCandidate] = []
        var discardedItems: [MemoryDistillationDiscardedItem] = buffer.pendingBundles
            .filter { $0.status != .closed }
            .map { bundle in
                MemoryDistillationDiscardedItem(
                    bundleID: bundle.id,
                    reason: "bundle_not_closed",
                    summary: bundle.userMessages.first?.content ?? bundle.artifacts.first?.summary ?? ""
                )
            }

        for bundle in closedBundles {
            let candidate = candidate(for: bundle, sourceRef: sourceRefByBundleID[bundle.id])
            guard passesQualityGate(candidate) else {
                discardedItems.append(MemoryDistillationDiscardedItem(
                    bundleID: bundle.id,
                    reason: "quality_gate_rejected",
                    summary: candidate.title
                ))
                continue
            }
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
        let reasons = triggerReasons ?? buffer.triggerReasons(at: date)
        let inputText = closedBundles.map { renderBundle($0) }.joined(separator: "\n\n")
        let outputText = (
            episodeCandidates
                + profileFactCandidates
                + decisionCandidates
                + projectFactCandidates
                + preferenceCandidates
                + unresolvedQuestions
                + riskFlags
        ).map(\.content).joined(separator: "\n\n")
        let trace = MemoryDistillationTrace(
            model: modelName,
            promptVersion: promptVersion,
            inputBundleCount: closedBundles.count,
            inputTokenEstimate: estimateTokens(inputText),
            outputTokenEstimate: estimateTokens(outputText),
            triggerReasons: reasons,
            createdAt: date,
            metadata: [
                "distiller": "deterministic",
                "quality_gate_minimum_content_characters": "\(qualityGatePolicy.minimumContentCharacters)",
                "quality_gate_minimum_importance": "\(qualityGatePolicy.minimumImportance)",
                "quality_gate_minimum_confidence": "\(qualityGatePolicy.minimumConfidence)"
            ]
        )
        return MemoryDistillationResult(
            sessionID: buffer.sessionID,
            sourceBufferID: buffer.id,
            episodeCandidates: episodeCandidates,
            profileFactCandidates: profileFactCandidates,
            decisionCandidates: decisionCandidates,
            projectFactCandidates: projectFactCandidates,
            preferenceCandidates: preferenceCandidates,
            discardedItems: discardedItems,
            unresolvedQuestions: unresolvedQuestions,
            riskFlags: riskFlags,
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

    private func candidate(for bundle: ConversationTurnBundle, sourceRef: MemoryDistillationSourceRef?) -> MemoryDistillationCandidate {
        let firstUserMessage = bundle.userMessages.first?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Conversation turn"
        let title = String(firstUserMessage.prefix(80))
        let content = renderBundle(bundle)
        let kind = classify(bundle: bundle, renderedContent: content)
        let score = score(kind: kind, renderedContent: content)
        return MemoryDistillationCandidate(
            kind: kind,
            title: title.isEmpty ? defaultTitle(for: kind) : title,
            content: content,
            rationale: rationale(for: kind),
            importance: score.importance,
            confidence: score.confidence,
            sourceRefIDs: sourceRef.map { [$0.id] } ?? [],
            status: .proposed,
            metadata: [
                "bundle_id": bundle.id,
                "session_id": bundle.sessionID,
                "candidate_origin": "memory_staging_buffer",
                "classification_method": "deterministic_keywords"
            ]
        )
    }

    private func passesQualityGate(_ candidate: MemoryDistillationCandidate) -> Bool {
        let trimmedContent = candidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.count >= qualityGatePolicy.minimumContentCharacters else { return false }
        guard candidate.importance >= qualityGatePolicy.minimumImportance else { return false }
        guard candidate.confidence >= qualityGatePolicy.minimumConfidence else { return false }
        return !isLowValueChitChat(trimmedContent)
    }

    private func classify(bundle: ConversationTurnBundle, renderedContent: String) -> MemoryDistillationCandidateKind {
        let text = renderedContent.lowercased()
        if containsAny(text, ["risk", "风险", "危险", "blocked", "blocker", "故障", "失败"]) {
            return .riskFlag
        }
        if containsAny(text, ["决定", "decision", "decided", "已确定", "采用", "不再", "改为"]) {
            return .decision
        }
        if containsAny(text, ["喜欢", "偏好", "prefer", "preference", "记住我", "请记住", "习惯", "不喜欢"]) {
            return .preference
        }
        if containsAny(text, ["项目", "project", "架构", "实现", "repository", "worker", "service", "pipeline", "分支", "commit", "pr "]) {
            return .projectFact
        }
        if containsAny(text, ["未解决", "待确认", "不知道", "open question", "todo", "?"]) {
            return .unresolvedQuestion
        }
        if containsAny(text, ["我是", "我的", "profile", "persona", "身份", "职业"]) {
            return .profileFact
        }
        return .episode
    }

    private func score(kind: MemoryDistillationCandidateKind, renderedContent: String) -> (importance: Double, confidence: Double) {
        let lengthBoost = min(0.15, Double(renderedContent.count) / 1_000.0)
        switch kind {
        case .preference, .decision:
            return (0.85 + lengthBoost, 0.82)
        case .projectFact:
            return (0.75 + lengthBoost, 0.78)
        case .profileFact:
            return (0.7 + lengthBoost, 0.7)
        case .riskFlag:
            return (0.9 + lengthBoost, 0.75)
        case .unresolvedQuestion:
            return (0.65 + lengthBoost, 0.65)
        case .episode:
            return (0.5 + lengthBoost, 0.7)
        }
    }

    private func rationale(for kind: MemoryDistillationCandidateKind) -> String {
        switch kind {
        case .episode:
            return "Closed conversation turn is useful as an episodic source for graph extraction."
        case .profileFact:
            return "Conversation appears to contain stable user/profile information."
        case .decision:
            return "Conversation appears to record an explicit decision."
        case .projectFact:
            return "Conversation appears to contain project or implementation state."
        case .preference:
            return "Conversation appears to contain a user preference or operating preference."
        case .unresolvedQuestion:
            return "Conversation appears to contain an unresolved question or follow-up item."
        case .riskFlag:
            return "Conversation appears to contain a risk, blocker, or failure signal."
        }
    }

    private func defaultTitle(for kind: MemoryDistillationCandidateKind) -> String {
        switch kind {
        case .episode: "Conversation turn"
        case .profileFact: "Profile fact"
        case .decision: "Decision"
        case .projectFact: "Project fact"
        case .preference: "Preference"
        case .unresolvedQuestion: "Unresolved question"
        case .riskFlag: "Risk flag"
        }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0.lowercased()) }
    }

    private func isLowValueChitChat(_ text: String) -> Bool {
        let acknowledgements: Set<String> = ["ok", "okay", "好的", "谢谢", "thanks", "收到", "嗯", "好", "yes", "是"]
        let lines = text
            .lowercased()
            .split(separator: "\n")
            .map { line in
                String(line)
                    .replacingOccurrences(of: "user:", with: "")
                    .replacingOccurrences(of: "assistant:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return true }
        return lines.allSatisfy { acknowledgements.contains($0) }
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
