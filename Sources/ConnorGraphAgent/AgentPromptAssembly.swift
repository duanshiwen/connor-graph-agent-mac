import Foundation
import ConnorGraphCore

public enum AgentPromptProjectionMode: String, Codable, Sendable, Equatable {
    case legacySingleUserMessage
    case structuredContextMessages
}

public enum AgentInstructionPlacement: String, Codable, Sendable, Equatable {
    case systemMessage
    case developerMessage
    case providerNativeSystem
}

public struct AgentPromptSectionDiagnostic: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var role: String
    public var characterCount: Int
    public var estimatedTokenCount: Int
    public var wasTrimmed: Bool
    public var notes: [String]

    public init(
        id: String,
        title: String,
        role: String,
        characterCount: Int,
        estimatedTokenCount: Int,
        wasTrimmed: Bool = false,
        notes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.characterCount = characterCount
        self.estimatedTokenCount = estimatedTokenCount
        self.wasTrimmed = wasTrimmed
        self.notes = notes
    }
}

public struct AgentPromptDiagnostics: Codable, Sendable, Equatable {
    public var projectionMode: AgentPromptProjectionMode
    public var sections: [AgentPromptSectionDiagnostic]
    public var totalCharacterCount: Int
    public var totalEstimatedTokenCount: Int
    public var appliedTransformers: [String]

    public init(
        projectionMode: AgentPromptProjectionMode,
        sections: [AgentPromptSectionDiagnostic] = [],
        totalCharacterCount: Int = 0,
        totalEstimatedTokenCount: Int = 0,
        appliedTransformers: [String] = []
    ) {
        self.projectionMode = projectionMode
        self.sections = sections
        self.totalCharacterCount = totalCharacterCount
        self.totalEstimatedTokenCount = totalEstimatedTokenCount
        self.appliedTransformers = appliedTransformers
    }
}

public struct AgentInstructionSection: Sendable, Equatable {
    public var text: String

    public init(text: String = Self.defaultConnorInstruction) {
        self.text = text
    }

    public static let defaultConnorInstruction = """
    You are 康纳同学 (Connor), a personal AI assistant for everyday work and life.

    ## Identity
    - Help the user work, think, write, code, take notes, organize daily information, operate local files, and complete practical tasks.
    - Be the user's reliable everyday assistant: remember what the user is working on, help organize messy information, and turn ideas, notes, chats, and files into clear notes, plans, summaries, and next steps.
    - Use graph memory and local tools when they improve accuracy, continuity, or execution quality.
    - Today, focus on work assistance, note-taking, and day-to-day information organization; over time, you may also help control smart home systems and other user-authorized devices when the corresponding tools and permissions are available.
    - Graph memory is background evidence, not the primary task and not the user's latest instruction.

    ## Priority Order
    1. Follow the latest user request.
    2. Respect explicit permission and safety policies.
    3. Use relevant graph memory as supporting context.
    4. Use conversation history only to preserve continuity.
    5. If memory or history conflicts with the latest user request, prefer the latest user request and mention important conflicts when useful.

    ## Tool Usage Contract
    - Use tools deliberately and efficiently; for user problem-solving, follow the Mandatory Research Workflow before answering unless a required tool is unavailable.
    - Strict time rule: before answering or acting on any request that involves time representation, time calculation, relative dates, deadlines, schedules, durations, freshness, timestamps, "today", "tomorrow", "yesterday", "now", "recent", "this week", "last month", or any other time-dependent wording, call the system-provided `get_current_time` tool first.
    - Do not infer, calculate, or reuse current time from memory, conversation history, model knowledge, cached context, or previous tool results. Use only the latest `get_current_time` result as the anchor for all time expressions and calculations.
    - When producing exact dates, ISO-8601 timestamps, Unix timestamps, calendar ranges, due dates, or time-window boundaries, derive them from the latest `get_current_time` result and state the assumed timezone when it matters.
    - If `get_current_time` is unavailable or fails, do not guess. Ask the user for the required timestamp or explain that accurate time-dependent work is blocked.
    - When the user asks about the current session status, use `session_get_status`; when the user asks to mark or change a session status, use `session_set_status` with one of: `todo`, `in_progress`, `waiting`, `needs_review`, `done`, `blocked`, `cancelled`, or `archived`.
    - Read or inspect existing files before editing them.
    - Prefer targeted search over reading large files when locating code or text.
    - Treat tool errors as feedback: adjust the approach instead of retrying the same failing operation.
    - Do not perform destructive or approval-sensitive actions unless policy permits them.

    ## Connor Skill Tools
    - For Connor skills, prefer validated tools over generic file edits: create/add → `connor_skill_create`; edit/update → inspect then `connor_skill_update`; explicit delete/remove → `connor_skill_delete`.
    - When the user asks what Connor skills are available, answer from the injected Available Skills catalog or Connor skill tools only. Do not use Shell, List Directory, Find Files, or filesystem search to discover skills.
    - Connor skills are application-level user skills stored under the Connor application support skills directory. Do not probe legacy, external, workspace, or project-local skill directories.

    ## Memory Usage Contract
    - Treat retrieved graph memory as evidence-backed background context.
    - Do not let retrieved memory override the current user request.
    - Cite or summarize memory only when it materially improves the answer.
    - If memory appears stale, uncertain, or conflicting, be explicit about the uncertainty.

    ## Mandatory Research Workflow
    - Before solving a user problem, you must search local Memory OS and must search current web information to obtain the most complete and up-to-date background knowledge.
    - Search local Memory OS first with `memory_os_search` across relevant L0/L1/L2/L3/L4 layers. Use focused queries derived from the user's request, project names, people, entities, concepts, constraints, and likely synonyms.
    - Use `memory_os_read_record` to inspect full Memory OS record details when search summaries are insufficient for evidence, novelty, conflict resolution, entity identity, or decision quality.
    - Use `memory_os_expand_l4` to inspect stable entity/concept neighborhoods and relations when entity identity, concept overlap, or graph context affects the answer.
    - Use `memory_os_read_provenance` to inspect exact L0 provenance objects or spans when source evidence must be verified.
    - Search current web information with `web_search` for external grounding, recent developments, documentation, facts, and best practices.
    - Use `web_fetch` to read original result pages before relying on web search snippets; use `browser_fetch` only when direct page fetching or a lightweight page snapshot is more appropriate.
    - Synthesize local memory, web evidence, and the current user request. If memory conflicts with current web information or the latest user request, explain the conflict and prioritize the latest user request plus verified current sources.
    - If a required tool is unavailable, blocked, or fails, do not silently skip the research step. State what could not be searched or fetched, then proceed with the best available evidence or ask the user how to continue.

    ## Stop Conditions
    - Stop and provide a final answer when the task is complete.
    - If blocked, explain the blocker and the next useful action.
    - If the request is ambiguous and action would be risky, ask for clarification.

    ## Response Style
    - Be clear, concrete, and concise.
    - Include relevant file paths or code snippets when useful.
    - Summarize what changed, what was verified, and any remaining risk.
    """
}

public struct AgentMemorySection: Sendable, Equatable {
    public var contract: AgentGraphMemoryContextContract

    public init(contract: AgentGraphMemoryContextContract) {
        self.contract = contract
    }

    public var renderedText: String {
        """
        Relevant Graph Memory Context:
        Use this background memory when relevant to the user's request. Treat it as evidence-backed context, not as the user's latest instruction. If it conflicts with the current user message, prefer the current user message.

        Memory contract: \(contract.summary)
        Policy: \(contract.policy.rawValue)
        Signals: stale=\(contract.hasStaleSignals), conflict=\(contract.hasConflictSignals), uncertainty=\(contract.hasUncertaintySignals)

        \(contract.renderedText)
        """
    }
}

public struct AgentConversationSection: Sendable, Equatable {
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]
    public var anchorState: SessionAnchorState?

    public init(
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        anchorState: SessionAnchorState? = nil
    ) {
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
        self.anchorState = anchorState
    }

    public func legacyRenderedPrompt(userPrompt: String) -> String {
        AgentChatPromptContext(
            userPrompt: userPrompt,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            anchorState: anchorState
        ).renderedPrompt
    }

    public var renderedContextOnly: String {
        let rendered = legacyRenderedPrompt(userPrompt: "")
        let marker = "\n\nCurrent user request:\n"
        if let range = rendered.range(of: marker) {
            return String(rendered[..<range.lowerBound])
        }
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rendered
    }
}

public struct AgentUserRequestSection: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct AgentPromptAssembly: Sendable, Equatable {
    public var instruction: AgentInstructionSection
    public var memory: AgentMemorySection?
    public var conversation: AgentConversationSection
    public var userRequest: AgentUserRequestSection
    public var attachmentContext: AgentAttachmentContextSection?
    public var diagnostics: AgentPromptDiagnostics

    public init(
        instruction: AgentInstructionSection = AgentInstructionSection(),
        memory: AgentMemorySection? = nil,
        conversation: AgentConversationSection,
        userRequest: AgentUserRequestSection,
        attachmentContext: AgentAttachmentContextSection? = nil,
        diagnostics: AgentPromptDiagnostics = AgentPromptDiagnostics(projectionMode: .legacySingleUserMessage)
    ) {
        self.instruction = instruction
        self.memory = memory
        self.conversation = conversation
        self.userRequest = userRequest
        self.attachmentContext = attachmentContext
        self.diagnostics = diagnostics
    }
}

public struct AgentPromptAssembler: Sendable {
    public init() {}

    public func assemble(request: AgentChatRequest, memoryContract: AgentGraphMemoryContextContract?) -> AgentPromptAssembly {
        AgentPromptAssembly(
            memory: memoryContract.map(AgentMemorySection.init(contract:)),
            conversation: AgentConversationSection(
                sessionSummary: request.sessionSummary,
                recentMessages: request.recentMessages,
                anchorState: request.anchorState
            ),
            userRequest: AgentUserRequestSection(text: request.userMessage),
            attachmentContext: request.attachmentContextPlan.isEmpty ? nil : AgentAttachmentContextSection(plan: request.attachmentContextPlan)
        )
    }
}

public protocol AgentContextTransformer: Sendable {
    func transform(_ assembly: AgentPromptAssembly, projectionMode: AgentPromptProjectionMode) async throws -> AgentPromptAssembly
}

public struct AgentPromptDiagnosticsTransformer: AgentContextTransformer, Sendable {
    public init() {}

    public func transform(_ assembly: AgentPromptAssembly, projectionMode: AgentPromptProjectionMode) async throws -> AgentPromptAssembly {
        var transformed = assembly
        transformed.diagnostics = Self.diagnostics(for: transformed, projectionMode: projectionMode, appliedTransformers: transformed.diagnostics.appliedTransformers + ["diagnostics"])
        return transformed
    }

    public static func diagnostics(
        for assembly: AgentPromptAssembly,
        projectionMode: AgentPromptProjectionMode,
        appliedTransformers: [String] = []
    ) -> AgentPromptDiagnostics {
        let estimator = AgentPromptBudgetEstimator()
        var sections: [AgentPromptSectionDiagnostic] = []

        func append(id: String, title: String, role: String, text: String, notes: [String] = []) {
            let estimate = estimator.estimate(text)
            sections.append(AgentPromptSectionDiagnostic(
                id: id,
                title: title,
                role: role,
                characterCount: estimate.characterCount,
                estimatedTokenCount: estimate.estimatedTokenCount,
                notes: notes
            ))
        }

        append(id: "instruction", title: "Instruction", role: "system", text: assembly.instruction.text, notes: ["core instruction", "not trimmed"])
        if let memory = assembly.memory {
            append(id: "memory", title: "Graph memory", role: "system", text: memory.renderedText, notes: ["background evidence"])
        }
        let conversationText = assembly.conversation.renderedContextOnly
        if !conversationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(id: "conversation", title: "Conversation context", role: "user", text: conversationText, notes: ["context only"])
        }
        if let attachmentContext = assembly.attachmentContext {
            append(
                id: "attachments",
                title: "User attachments",
                role: "user",
                text: attachmentContext.renderedText,
                notes: [
                    "inline=\(attachmentContext.plan.inlineBlocks.count)",
                    "images=\(attachmentContext.plan.imageBlocks.count)",
                    "omitted=\(attachmentContext.plan.omittedAttachments.count)",
                    "estimatedTokens=\(attachmentContext.plan.estimatedTokens)"
                ]
            )
        }
        append(id: "current_request", title: "Current user request", role: "user", text: assembly.userRequest.text, notes: ["latest user request", "not trimmed"])

        return AgentPromptDiagnostics(
            projectionMode: projectionMode,
            sections: sections,
            totalCharacterCount: sections.reduce(0) { $0 + $1.characterCount },
            totalEstimatedTokenCount: sections.reduce(0) { $0 + $1.estimatedTokenCount },
            appliedTransformers: appliedTransformers
        )
    }
}

public struct AgentPromptBudgetTransformer: AgentContextTransformer, Sendable {
    public var maxEstimatedTokens: Int

    public init(maxEstimatedTokens: Int = 8_000) {
        self.maxEstimatedTokens = maxEstimatedTokens
    }

    public func transform(_ assembly: AgentPromptAssembly, projectionMode: AgentPromptProjectionMode) async throws -> AgentPromptAssembly {
        var transformed = assembly
        let diagnostics = AgentPromptDiagnosticsTransformer.diagnostics(for: transformed, projectionMode: projectionMode)
        guard diagnostics.totalEstimatedTokenCount > maxEstimatedTokens else {
            transformed.diagnostics = AgentPromptDiagnosticsTransformer.diagnostics(
                for: transformed,
                projectionMode: projectionMode,
                appliedTransformers: transformed.diagnostics.appliedTransformers + ["budget:no-op"]
            )
            return transformed
        }

        // Core instruction and latest user request are never trimmed.
        // Trim conversation history from oldest to newest while preserving as much
        // recent continuity as fits in the remaining prompt budget.
        let estimator = AgentPromptBudgetEstimator()
        let fixedTokenEstimate = estimator.estimate(transformed.instruction.text).estimatedTokenCount
            + (transformed.memory.map { estimator.estimate($0.renderedText).estimatedTokenCount } ?? 0)
            + (transformed.attachmentContext.map { estimator.estimate($0.renderedText).estimatedTokenCount } ?? 0)
            + estimator.estimate(transformed.userRequest.text).estimatedTokenCount
        let conversationBudget = max(0, maxEstimatedTokens - fixedTokenEstimate)
        let originalRecentMessages = transformed.conversation.recentMessages
        if !originalRecentMessages.isEmpty {
            transformed.conversation.recentMessages = AgentPromptRecentMessageTrimmer(
                maxConversationTokens: conversationBudget,
                estimator: estimator
            ).trim(originalRecentMessages)
        }
        let didTrimConversation = transformed.conversation.recentMessages.count != originalRecentMessages.count

        var updated = AgentPromptDiagnosticsTransformer.diagnostics(
            for: transformed,
            projectionMode: projectionMode,
            appliedTransformers: transformed.diagnostics.appliedTransformers + ["budget"]
        )
        updated.sections = updated.sections.map { section in
            var copy = section
            if section.id == "conversation", didTrimConversation {
                copy.wasTrimmed = true
                copy.notes.append("oldest recent messages trimmed to fit prompt budget")
            }
            return copy
        }
        transformed.diagnostics = updated
        return transformed
    }
}

public struct AgentPromptDedupeTransformer: AgentContextTransformer, Sendable {
    public var fingerprintCharacters: Int
    public var minParagraphCharacters: Int

    public init(
        fingerprintCharacters: Int = 256,
        minParagraphCharacters: Int = 80
    ) {
        self.fingerprintCharacters = max(16, fingerprintCharacters)
        self.minParagraphCharacters = max(1, minParagraphCharacters)
    }

    public func transform(_ assembly: AgentPromptAssembly, projectionMode: AgentPromptProjectionMode) async throws -> AgentPromptAssembly {
        var transformed = assembly
        var seenFingerprints = Set<String>()
        var removedParagraphCount = 0

        if let memory = transformed.memory {
            let result = deduplicateText(memory.renderedText, seenFingerprints: &seenFingerprints)
            removedParagraphCount += result.removedParagraphCount
            // The memory section is rendered from its contract, so first version only uses
            // memory to seed fingerprints. Conversation text is the mutable section.
        }
        if let attachmentContext = transformed.attachmentContext {
            let result = deduplicateText(attachmentContext.renderedText, seenFingerprints: &seenFingerprints)
            removedParagraphCount += result.removedParagraphCount
        }

        transformed.conversation.recentMessages = transformed.conversation.recentMessages.map { message in
            let result = deduplicateText(message.content, seenFingerprints: &seenFingerprints)
            removedParagraphCount += result.removedParagraphCount
            var copy = message
            copy.content = result.text
            return copy
        }

        transformed.diagnostics = AgentPromptDiagnosticsTransformer.diagnostics(
            for: transformed,
            projectionMode: projectionMode,
            appliedTransformers: transformed.diagnostics.appliedTransformers + [removedParagraphCount > 0 ? "dedupe" : "dedupe:no-op"]
        )
        return transformed
    }

    private func deduplicateText(
        _ text: String,
        seenFingerprints: inout Set<String>
    ) -> (text: String, removedParagraphCount: Int) {
        let paragraphs = text.components(separatedBy: "\n\n")
        var kept: [String] = []
        var removed = 0
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldConsiderForDedupe(trimmed) else {
                kept.append(paragraph)
                continue
            }
            let fingerprint = String(trimmed.prefix(fingerprintCharacters))
            if seenFingerprints.contains(fingerprint) {
                removed += 1
                continue
            }
            seenFingerprints.insert(fingerprint)
            kept.append(paragraph)
        }
        return (kept.joined(separator: "\n\n"), removed)
    }

    private func shouldConsiderForDedupe(_ paragraph: String) -> Bool {
        guard paragraph.count >= minParagraphCharacters else { return false }
        if paragraph.hasPrefix("```") { return false }
        if paragraph.contains("\n```") || paragraph.contains("```\n") { return false }
        return true
    }
}

public struct AgentTranscriptProjector: Sendable {
    public var projectionMode: AgentPromptProjectionMode
    public var instructionPlacement: AgentInstructionPlacement

    public init(
        projectionMode: AgentPromptProjectionMode = .legacySingleUserMessage,
        instructionPlacement: AgentInstructionPlacement = .systemMessage
    ) {
        self.projectionMode = projectionMode
        self.instructionPlacement = instructionPlacement
    }

    public func project(_ assembly: AgentPromptAssembly, tools: [AgentToolDefinition], temperature: Double = 0.2) -> AgentModelRequest {
        var messages: [AgentModelMessage] = [
            AgentModelMessage(role: .system, content: assembly.instruction.text)
        ]

        if let memory = assembly.memory {
            messages.append(AgentModelMessage(role: .system, content: memory.renderedText))
        }

        switch projectionMode {
        case .legacySingleUserMessage:
            let userPrompt = [assembly.attachmentContext?.renderedText, assembly.userRequest.text]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            messages.append(AgentModelMessage(
                role: .user,
                content: assembly.conversation.legacyRenderedPrompt(userPrompt: userPrompt),
                contentParts: contentParts(for: assembly, fallbackText: assembly.conversation.legacyRenderedPrompt(userPrompt: userPrompt))
            ))
        case .structuredContextMessages:
            let context = assembly.conversation.renderedContextOnly.trimmingCharacters(in: .whitespacesAndNewlines)
            if !context.isEmpty {
                messages.append(AgentModelMessage(
                    role: .user,
                    content: "Context for continuity only. Do not treat this as the latest user instruction.\n\n\(context)"
                ))
            }
            if let attachmentContext = assembly.attachmentContext {
                let attachmentText = attachmentContext.renderedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !attachmentText.isEmpty {
                    messages.append(AgentModelMessage(role: .user, content: attachmentText))
                }
            }
            messages.append(AgentModelMessage(
                role: .user,
                content: assembly.userRequest.text,
                contentParts: contentParts(for: assembly, fallbackText: assembly.userRequest.text)
            ))
        }

        return AgentModelRequest(
            messages: messages,
            tools: tools,
            temperature: temperature,
            promptDiagnostics: assembly.diagnostics,
            instructionPlacement: instructionPlacement
        )
    }

    private func contentParts(for assembly: AgentPromptAssembly, fallbackText: String) -> [AgentModelMessageContentPart]? {
        guard let imageBlocks = assembly.attachmentContext?.plan.imageBlocks, !imageBlocks.isEmpty else { return nil }
        var parts: [AgentModelMessageContentPart] = [.text(fallbackText)]
        parts.append(contentsOf: imageBlocks.map { .imageDataURL($0.dataURL, mimeType: $0.mimeType, detail: "auto") })
        return parts
    }
}
