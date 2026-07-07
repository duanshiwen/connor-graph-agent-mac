import Foundation
import ConnorGraphCore

public struct PersonContextSnapshot: Sendable, Codable, Equatable, Hashable {
    public var profile: PersonProfile
    public var memorySummary: String?
    public var activeAliases: [String]
    public var activeMemoryItems: [String]

    public init(profile: PersonProfile, memorySummary: String? = nil, activeAliases: [String]? = nil, activeMemoryItems: [String] = []) {
        self.profile = profile
        self.memorySummary = memorySummary
        self.activeAliases = activeAliases ?? profile.aliases
        self.activeMemoryItems = activeMemoryItems
    }
}

public struct AgentChatPromptContext: Sendable, Equatable {
    public var userPrompt: String
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]
    public var explicitPersonContexts: [PersonContextSnapshot]
    /// Compression anchor state — takes priority over `sessionSummary`
    /// when both are present.
    public var anchorState: SessionAnchorState?

    public init(
        userPrompt: String,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        explicitPersonContexts: [PersonContextSnapshot] = [],
        anchorState: SessionAnchorState? = nil
    ) {
        self.userPrompt = userPrompt
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
        self.explicitPersonContexts = explicitPersonContexts
        self.anchorState = anchorState
    }

    public var renderedPrompt: String {
        var blocks: [String] = []

        // Anchor state takes priority over session summary
        if let anchor = anchorState, anchor.compressionCycles > 0 {
            blocks.append(renderAnchorState(anchor))
        } else if !trimmedSummaryContent.isEmpty {
            blocks.append("""
            Previous session summary:
            \(trimmedSummaryContent)
            """)
        }

        if !recentMessages.isEmpty {
            let renderedMessages = recentMessages.map(Self.render).joined(separator: "\n")
            blocks.append("""
            Recent conversation:
            \(renderedMessages)
            """)
        }

        if !explicitPersonContexts.isEmpty {
            blocks.append(renderExplicitPersonContexts(explicitPersonContexts))
        }

        // Only add the "Current user request" prefix if there's context to prepend
        if !blocks.isEmpty {
            blocks.append("""
            Current user request:
            \(userPrompt)
            """)
            return blocks.joined(separator: "\n\n")
        }
        
        return userPrompt
    }

    public var inspection: AgentChatPromptInspection {
        let renderedPrompt = renderedPrompt
        let estimator = AgentPromptBudgetEstimator()
        let estimate = estimator.estimate(renderedPrompt)
        return AgentChatPromptInspection(
            includesSummary: !trimmedSummaryContent.isEmpty || anchorState != nil,
            recentMessageCount: recentMessages.count,
            currentRequest: userPrompt,
            renderedPrompt: renderedPrompt,
            renderedPromptCharacterCount: estimate.characterCount,
            estimatedPromptTokenCount: estimate.estimatedTokenCount,
            promptBudgetStatus: estimator.status(estimatedTokenCount: estimate.estimatedTokenCount)
        )
    }

    /// Whether this context was built from a compression anchor.
    public var isCompressed: Bool {
        (anchorState?.compressionCycles ?? 0) > 0
    }

    // MARK: - Private

    private var trimmedSummaryContent: String {
        sessionSummary?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func renderExplicitPersonContexts(_ contexts: [PersonContextSnapshot]) -> String {
        var lines: [String] = [
            "Explicit Relationship Context:",
            "The user explicitly mentioned these relationship-aware Person Registry entries in the current message. Treat each entry as a relationship identity anchor for this turn and prefer it for person fact attribution."
        ]
        for context in contexts {
            let profile = context.profile
            let aliases = context.activeAliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
            var parts: [String] = [
                "- \(profile.displayName) (person_id: \(profile.id.rawValue))"
            ]
            if !aliases.isEmpty { parts.append("aliases: \(aliases)") }
            if let organization = profile.organizationName, !organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("organization: \(organization)")
            }
            if let jobTitle = profile.jobTitle, !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("job_title: \(jobTitle)")
            }
            if let notes = profile.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("notes: \(notes)")
            }
            if let memorySummary = context.memorySummary, !memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("memory: \(memorySummary)")
            }
            let activeMemoryItems = context.activeMemoryItems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !activeMemoryItems.isEmpty {
                let bullets = activeMemoryItems.prefix(8).map { "- \($0)" }.joined(separator: "\n")
                parts.append("active person memory (archived/deleted/moved person memories are not active default context): \n\(bullets)")
            }
            if let memoryStableKey = profile.memoryStableKey, !memoryStableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("memory_stable_key: \(memoryStableKey)")
            }
            lines.append(parts.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private func renderAnchorState(_ anchor: SessionAnchorState) -> String {
        var lines: [String] = [
            "Session context (compressed from \(anchor.compressionCycles) prior rounds):",
            "- Intent: \(anchor.intent)",
        ]
        if !anchor.decisions.isEmpty {
            lines.append("- Key decisions: \(anchor.decisions.joined(separator: "; "))")
        }
        if !anchor.changes.isEmpty {
            lines.append("- Changes made: \(anchor.changes.joined(separator: "; "))")
        }
        if !anchor.pendingWork.isEmpty {
            lines.append("- Pending work: \(anchor.pendingWork.joined(separator: "; "))")
        }
        if !anchor.preservedDetails.isEmpty {
            lines.append("- Important details: \(anchor.preservedDetails)")
        }
        return lines.joined(separator: "\n")
    }

    private static func render(message: AgentMessage) -> String {
        switch message.role {
        case .user:
            return "User: \(message.content)"
        case .assistant:
            return "Assistant: \(message.content)"
        case .system:
            return "System: \(message.content)"
        }
    }
}
