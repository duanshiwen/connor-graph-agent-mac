import Foundation

public struct AssistantAttentionSection: Codable, Sendable, Equatable {
    public var source: String
    public var summary: String
    public var error: String?

    public init(source: String, summary: String, error: String? = nil) {
        self.source = source
        self.summary = summary
        self.error = error
    }

    public var hasCandidates: Bool {
        guard error == nil else { return false }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return true
        }
        if source == "rss_search_items", let rows = value as? [Any] {
            return !rows.isEmpty
        }
        if source == "attention_brief", let object = value as? [String: Any] {
            let events = object["events"] as? [Any] ?? []
            let mail = object["mail"] as? [String: Any]
            let messages = mail?["messages"] as? [Any] ?? []
            return !events.isEmpty || !messages.isEmpty
        }
        return true
    }
}

public struct AssistantAttentionPack: Codable, Sendable, Equatable {
    public var checkedAt: Date
    public var sections: [AssistantAttentionSection]

    public init(checkedAt: Date, sections: [AssistantAttentionSection]) {
        self.checkedAt = checkedAt
        self.sections = sections
    }

    public var hasAvailableSources: Bool {
        sections.contains { $0.error != AssistantAttentionCoordinator.capabilityUnavailableError }
    }

    public var hasCandidates: Bool {
        sections.contains { $0.hasCandidates }
    }
}

public struct AssistantAttentionCoordinator: Sendable {
    public static let internalToolNames: Set<String> = ["attention_brief", "rss_search_items"]
    public static let capabilityUnavailableError = "capability unavailable"

    public var maximumSectionCharacters: Int
    public var maximumPackTokens: Int

    public init(maximumSectionCharacters: Int = 6_000, maximumPackTokens: Int = 3_000) {
        self.maximumSectionCharacters = max(500, maximumSectionCharacters)
        self.maximumPackTokens = max(512, maximumPackTokens)
    }

    public func run(
        request: AgentChatRequest,
        registry: AgentToolRegistry,
        policy: AgentPolicyEngine,
        now: Date = Date()
    ) async -> AssistantAttentionPack {
        let specs = attentionSpecs(now: now)
        var sections: [AssistantAttentionSection] = []
        await withTaskGroup(of: AssistantAttentionSection.self) { group in
            for spec in specs {
                guard registry.definition(named: spec.name) != nil else {
                    sections.append(.init(source: spec.name, summary: "", error: Self.capabilityUnavailableError))
                    continue
                }
                group.addTask {
                    let callID = "assistant-attention-\(spec.name)-\(UUID().uuidString)"
                    let call = AgentToolCall(
                        id: callID,
                        runID: request.runID,
                        sessionID: request.sessionID,
                        name: spec.name,
                        argumentsJSON: spec.argumentsJSON
                    )
                    let context = AgentToolExecutionContext(
                        runID: request.runID,
                        sessionID: request.sessionID,
                        groupID: request.groupID,
                        userPrompt: request.userMessage,
                        toolCallID: callID,
                        policyEngine: policy,
                        currentUserMessageID: request.currentUserMessageID
                    )
                    do {
                        let result = try await registry.execute(call, context: context)
                        let content = result.contentJSON ?? result.contentText
                        return AssistantAttentionSection(
                            source: spec.name,
                            summary: compact(content, limit: maximumSectionCharacters),
                            error: result.error
                        )
                    } catch {
                        return AssistantAttentionSection(
                            source: spec.name,
                            summary: "",
                            error: String(describing: error)
                        )
                    }
                }
            }
            for await section in group { sections.append(section) }
        }
        let pack = AssistantAttentionPack(checkedAt: now, sections: sections.sorted { $0.source < $1.source })
        return enforceBudget(pack)
    }

    public func render(_ pack: AssistantAttentionPack) -> String {
        var lines = [
            "<assistant-final-attention>",
            "This read-only check was completed by the Runtime immediately before final synthesis.",
            "Mention only concrete items requiring immediate attention, preparation, or action. Silence is correct when nothing qualifies."
        ]
        for section in pack.sections {
            lines.append("[\(section.source)]")
            if let error = section.error {
                lines.append("unavailable: \(error)")
            } else if section.summary.isEmpty {
                lines.append("no candidates")
            } else {
                lines.append(section.summary)
            }
        }
        lines.append("</assistant-final-attention>")
        return lines.joined(separator: "\n")
    }

    private func attentionSpecs(now: Date) -> [AssistantAttentionToolSpec] {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: now.addingTimeInterval(-48 * 60 * 60))
        let end = formatter.string(from: now)
        return [
            .init(name: "attention_brief", argumentsJSON: #"{"days":2,"mailLimit":10}"#),
            .init(name: "rss_search_items", argumentsJSON: json([
                "query": "",
                "startDate": start,
                "endDate": end,
                "timeSort": "timeDescThenRelevance",
                "limit": 10
            ]))
        ]
    }

    private func enforceBudget(_ pack: AssistantAttentionPack) -> AssistantAttentionPack {
        let estimator = AgentPromptBudgetEstimator()
        guard estimator.estimate(render(pack)).estimatedTokenCount > maximumPackTokens else { return pack }
        var reduced = pack
        let perSection = max(200, maximumPackTokens * 3 / max(1, pack.sections.count))
        reduced.sections = reduced.sections.map {
            var section = $0
            section.summary = compact(section.summary, limit: perSection)
            return section
        }
        return reduced
    }

    private func compact(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
}

private struct AssistantAttentionToolSpec: Sendable {
    var name: String
    var argumentsJSON: String
}
