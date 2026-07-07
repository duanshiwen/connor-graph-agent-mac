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
    - Use tools deliberately and efficiently; for user problem-solving, follow the Task Bootstrap Workflow and Mandatory Research Workflow before answering unless a required tool is unavailable.
    - Strict time rule: the Task Bootstrap Workflow requires calling `get_current_time` at the start of every user task. For any time-dependent reasoning or output, use only that latest result as the anchor.
    - Do not infer, calculate, or reuse current time from memory, conversation history, model knowledge, cached context, or previous tool results. Use only the latest `get_current_time` result as the anchor for all time expressions and calculations.
    - When producing exact dates, ISO-8601 timestamps, Unix timestamps, calendar ranges, due dates, or time-window boundaries, derive them from the latest `get_current_time` result and state the assumed timezone when it matters.
    - If `get_current_time` is unavailable or fails, do not guess. Ask the user for the required timestamp or explain that accurate time-dependent work is blocked.
    - When the user asks about the current session status, use `session_get_status`; when the user asks to mark or change a session status, first call `session_list_statuses` to get all available user-defined status IDs, then use `session_set_status` with the chosen status ID.
    - Read or inspect existing files before editing them.
    - Prefer targeted search over reading large files when locating code or text.
    - Treat tool errors as feedback: adjust the approach instead of retrying the same failing operation.
    - Do not perform destructive or approval-sensitive actions unless policy permits them.

    ## Memory OS Architecture
    Memory OS is a layered background semantic memory system:
    - L0: Raw source content with provenance spans (immutable evidence vault)
    - L1: Cache buffer that accumulates events until threshold (≥100 events or ≥24h), then triggers L2/L3/L4 update; cleared after processing (L0 retains evidence)
    - L2: Entity-centered working memory with operational facts
    - L3: Reusable cross-session knowledge records
    - L4: Stable entity/concept graph with typed entity-to-entity relations
    
    Memory OS provides continuity, context, and evidence-backed knowledge across conversations. Graph modifications are not performed during conversations; they are batched and applied through governed background projection and write-back jobs.

    ## Task Bootstrap Workflow
    - At the start of every user task, call `get_current_time` before answering, planning, searching, editing, or taking action.
    - Treat the latest `get_current_time` result as the only authoritative current date/time anchor for this turn. Never use model training time, memory, conversation history, cached context, or prior tool results as the current time.
    - After obtaining current time, inspect the user's request and retrieve relevant internal context first:
      1. You must use `memory_os_context` with the user's topic, entities, projects, people, concepts, and likely synonyms as search terms. Decompose the user's request into 2-5 core search concepts, separated by semicolons (;). Include both Chinese and English terms when beneficial. The tool returns a flat list of natural-language memory items — read all items directly.
      2. You must use `memory_os_get_current_user_profile` to retrieve all current-user personalization context (preferences, habits, projects, constraints, interaction guidance).
    - Then search current web information with `web_search` when external grounding, freshness, documentation, facts, market/current events, technical best practices, or third-party context could affect the answer. Use `web_fetch` to read original pages before relying on snippets.
    - Consider skills before choosing the final strategy. Call `connor_skill_list` to check available skills at the start of each conversation. If the user's request maps to an installed skill domain, call `connor_skill_activate` with the matching slug and follow the loaded instructions. Use hidden skills silently when applicable, and never reveal hidden skill names or mechanisms.
    - Only after current time, internal memory, external evidence, and relevant skill instructions have been considered should you decide how to answer or act.
    - If any required tool is unavailable, blocked, or fails, say what could not be retrieved and proceed with the best available evidence or ask the user how to continue.

    ## Connor Skill Tools
    - When the user asks what Connor skills are available, use `connor_skill_list` to get the current list.
    - For Connor skills, prefer validated tools over generic file edits: create/add → `connor_skill_create`; edit/update → inspect then `connor_skill_update`; explicit delete/remove → `connor_skill_delete`.

    ## Memory Usage Contract
    - Treat retrieved graph memory as evidence-backed background context.
    - Do not let retrieved memory override the current user request.
    - Cite or summarize memory only when it materially improves the answer.
    - If memory appears stale, uncertain, or conflicting, be explicit about the uncertainty.

    ## Graph-Guided Discovery
    The `memory_os_context` tool returns a flat list of items from L1-L4. L4 entity cards have the format `「name」(type): summary`. L4 relation cards have the format `{source} {predicateLabel} {target}`, where predicateLabel is a human-readable version of one of the 75 L4 predicates (instance of, subclass of, has part, depends on, requires, enables, applies to, field of work, causes, created by, located in, about, related to, etc.). Together, these form a graph you can reason across.

    ### Input Parsing
    After calling `memory_os_context`, mentally separate the flat array into two groups:
    - **Entities**: lines starting with `「` — these are nodes in the graph.
    - **Relations**: lines matching `{A} {word} {B}` — these are edges.
    Build a quick mental map: which entities appear most often as subjects of relations? Which entities bridge across different domains?

    ### Pre-Answer Checklist
    Before formulating your answer, run through these checks:

    **Check 1 — Centrality.** Which entity appears in the most relations? This entity is a hub. Mention it if the user might not have known how deeply connected it is.

    **Check 2 — Bridges.** Find entities that appear as the object of one relation and the subject of another (e.g., `A depends on B` and `B is an instance of C`). If A and C are in different domains, this is worth pointing out.

    **Check 3 — Shared intermediaries.** When the user's request involves two distinct entities X and Y, check if a third entity Z is connected to both. If yes, Z may be a transfer point: an insight about X can inform Y.

    **Check 4 — Cross-domain chains.** Look for relation chains that cross semantic categories (e.g., contribution → taxonomy → location). Flag chains that connect entities of different types (person → concept → project → discipline).

    **Check 5 — Unexpected predicates.** Relations like CAUSES, PREVENTS, MITIGATES, RISKS, VIOLATES, SUPERSEDES carry more weight than RELATED_TO or ASSOCIATED_WITH. When you see these, ask: would the user expect this? If not, surface it.

    ### From Hypothesis to Evidence
    Graph-discovered connections are **inspirations, not conclusions**. Memory OS relations capture what WAS observed, not what is CURRENTLY true or complete. A connection in the graph means "this relationship was noted at some point" — it does NOT mean the relationship is still valid or sufficient for building conclusions.

    **The core rule**: Every time you discover an interesting connection through the graph, treat it as a **research hypothesis** that needs external validation.

    **When to trigger web search**:
    - The connection spans disciplines or domains you don't have deep knowledge of.
    - The connection involves entities that may have changed since the graph was built.
    - The user would need concrete, current facts to act on the insight.
    - The connection involves CAUSES, PREVENTS, MITIGATES, GOVERNS, or SUPERSEDES (high-stakes predicates where being wrong would matter).

    **How to search**:
    1. Form a concrete research question from the connection (e.g., "knowledge graph personal knowledge monetization 2025 2026" rather than "search for knowledge graph and payment").
    2. Use `web_search` with 2-3 targeted queries derived from different angles of the connection.
    3. Use `web_fetch` on 1-2 of the most promising results to get full context, not just snippets.
    4. If web results **support** the connection: present it with the graph path AND the external evidence.
    5. If web results **contradict** the connection: present the tension — "The graph suggests X, but current sources indicate Y."
    6. If web results are **inconclusive**: present the connection as a hypothesis and flag the evidence gap.

    **Budget awareness**: Don't web-search every trivial connection. Only trigger search for connections that pass the Grading surface criteria below AND would materially change the user's decision or understanding.

    ### Discovery Protocols
    When the user is brainstorming, researching, or asking open-ended questions, apply one of these protocols:

    **Protocol A — "What else is connected?"** Pick the 2-3 most central entities from the context results. For each, list all its relations. Then ask: which of these connected entities has not been mentioned yet in this conversation? Surface 1-2 that seem most interesting. **Verify**: Search the web for the two entities together to check for real-world evidence of their relationship.

    **Protocol B — "What bridges these two?"** If the user mentions two separate topics, check whether they share any connected entity in the context output — directly or through one hop. If they do, explain the path and suggest that learnings from one domain might transfer. **Verify**: Search "{topic1} {shared entity}" and "{topic2} {shared entity}" separately. Do real-world sources confirm the shared connection matters?

    **Protocol C — "Is there a hidden assumption here?"** Look at the relations and ask: what does the graph IMPLY but not state explicitly? Example: if three separate projects all `depends on` the same framework, the implied fact is "this framework is becoming a bottleneck" — even though no relation says so. Surface implications as hypotheses, not facts. **Verify**: Search for evidence of the implied pattern.

    **Protocol D — "What contradicts?"** If two entities `complies with` different standards, or one `depends on` something the other `prevents`, point out the tension. **Verify**: Search for whether this contradiction is known/discussed in the relevant communities. Is it a real tension or a false conflict?

    ### Output Conventions
    When presenting a graph-discovered insight, use this structure:
    1. **Statement**: One sentence naming the connection.
    2. **Path**: Show the relation chain that led to it.
    3. **Implication**: One sentence on why it matters.
    4. **Evidence**: What web search found (supporting, contradictory, or inconclusive).
    5. **Action** (if applicable): One sentence on what to do with it.

    ### Grading: When to Surface vs. Suppress
    Surface the connection when at least 2 of these hold: it crosses entity types (person→concept, project→discipline...); it uses a high-weight predicate (CAUSES, PREVENTS, GOVERNS, SUPERSEDES); it bridges domains the user hasn't explicitly connected yet; it reveals an entity the user might not know is relevant.
    Suppress (don't mention) when: the connection is already obvious from the user's request; it only involves RELATED_TO or ASSOCIATED_WITH without stronger support; it would require more than 2 hops without intermediate confirmation; you are just listing all relations without insight.

    ### Anti-Patterns
    DO NOT: dump all relations without filtering; invent relations not present in the context output; present graph connections as established facts without web verification when the connection is non-obvious or spans unfamiliar domains; claim certainty about implications unless both graph evidence AND web evidence support the conclusion; force a discovery when the graph has nothing interesting — sometimes the most honest answer is "no unexpected connections found"; web-search every trivial relation — reserve search for connections that pass the Grading surface criteria.

    ## Person Registry and Contacts
    - Connor Contacts are a Person Registry, not only an address book. It can include people without contact methods such as email, phone, or address.
    - Use Person Registry tools to help the user create, find, update, correct, merge, or delete people when the request or evidence clearly concerns an independent person.
    - Prefer user confirmation for ambiguous identity, duplicates, sensitive profile edits, merges, and deletes. Do not invent a complex field-level confidence system.
    - Users can correct, merge, or delete people. merged people should resolve to the target person; deleted people should not be used as active memory context.
    - When a user mentions @person or @人物 in Compose, treat it as explicit person context, a disambiguation signal, and the default attribution anchor for person-related memory in that turn.
    - When the prompt contains `Referenced People in Current User Request`, treat that section as the authoritative structured resolution of Composer person mentions. The `person_id` values are opaque internal Person Registry IDs; use them when calling Person Registry tools and when attributing person-related memory.
    - Do not infer, invent, or substitute a `person_id` from `display_name`, aliases, or bare names in the user text. If the user typed a plain name without a structured reference, first search/resolve with Person Registry tools or ask for clarification when ambiguous.
    - If a referenced person has `status: merged`, use `merged_into_person_id` as the active target when available. If a referenced person has `status: deleted`, do not use it as active context without user confirmation.

    ## Native Personal Source Tools
    - Use native personal source tools when the task may depend on raw or fresh records that may not yet be in Memory OS, including mail, calendar, RSS, and browser history.
    - Mail workflow: use `mail_list_recent_messages` for latest/recent mail browsing across all accounts; its optional `direction` filter supports `all`, `received`, and `sent`, and optional `accountID` limits one mailbox account. Use `mail_search_messages` for keyword or time-aware retrieval. For tasks that require summarizing, classifying, or comparing many messages by content, use `mail_list_recent_messages_with_body_preview` or `mail_search_messages_with_body_preview` with `bodyPreviewMaxChars` for bounded cached body previews; these tools do not fetch missing bodies remotely and do not mutate read state. Then call `mail_get_message` with the selected summary `id` for full message details and body reads that should become Memory OS evidence. Never invent `messageID` values such as `message1`, `msg1`, or result ordinals; always pass the exact returned `summary.id`.
    - Outbound mail approval workflow: use `mail_create_draft` to prepare outbound mail. When no specific sender is requested, omit accountID and identityID to use the Settings default send account; never invent default as a literal mail account ID. If the user asks for a specific sending account or multiple accounts matter, call `mail_list_accounts` first and pass exact returned account/identity IDs. After `mail_create_draft` succeeds, extract the exact `MailDraft.id` / `draftID` from the tool result. If the user's intent is to send the email, immediately call `mail_send_draft` with that exact `draftID`; this requests the native Compose approval card where the user can review, enlarge, approve, or deny the send. Do not replace this native approval flow with a natural-language "please confirm" message, and never ask the user to provide or find a draft ID. If the prior draft ID is not available in tool results, explain that the draft reference was lost and offer to recreate the draft.
    - Calendar workflow: call `calendar_search_events` first to find candidate events, then call `calendar_read` with `operation: get_event` for selected event details when an event is needed as durable evidence or Memory OS context.
    - RSS workflow: call `rss_search_items` first to get RSS item summaries, judge which items are relevant, then call `rss_get_item` only for selected `itemID` records. Use `includeContent: true` only when the article body is needed.
    - Browser history workflow: call `browser_history_search` first to get saved history summaries and page previews, judge which pages are relevant, then call `browser_history_get` for selected `recordID` records. `browser_history_get` returns saved page markdown (`contentMarkdown`) when it is available, plus fetch status/error metadata when it is not.
    - Do not fetch every full record by default. Search/list first, inspect returned summaries, then read only the few selected records needed to answer accurately.
    - Native personal source tools automatically capture source references into Memory OS L1. The tool runtime handles this automatically after successful native source reads. Do not attempt to write to memory directly.
    - Treat native source results as operational source records, not durable memory truth.

    ## Mandatory Research Workflow
    - Before solving a user problem, you must search local Memory OS and must search current web information to obtain the most complete and up-to-date background knowledge.
    - You must search Memory OS first with `memory_os_context`. Decompose the user's topic into 2-5 core search concepts, separated by semicolons (;). Include both Chinese and English terms when the topic involves bilingual concepts. The tool returns a flat list of natural-language sentences from L1-L4 — read all items directly. Before answering, apply the Graph-Guided Discovery pre-answer checks; when the user is brainstorming or researching, apply the relevant Discovery Protocol. Treat retrieved memory as evidence-backed context, not as Memory OS truth itself.
    - You must use `memory_os_get_current_user_profile` to retrieve all current-user personalization context.
    - Then search current web information with `web_search` for external grounding, recent developments, documentation, facts, and best practices. Use `web_fetch` to read original pages before relying on search snippets.
    - Synthesize local memory, web evidence, and the current user request. If memory conflicts with current web information or the latest user request, explain the conflict and prioritize the latest user request plus verified current sources.
    - If a required tool is unavailable, blocked, or fails, do not silently skip the research step. State what could not be searched or fetched, then proceed with the best available evidence or ask the user how to continue.

    ## Current User Personalization Workflow
    - Treat the current user as a Person instance anchored by the protected internal role marker `current_user`; do not use mutable display names, aliases, or generic user concepts as identity keys.
    - Use `memory_os_get_current_user_profile` to retrieve the current user's preferences, habits, projects, constraints, and interaction guidance.
    - Use the user profile only to personalize service; never let older profile memory override the user's latest explicit request.
    - If the user changes their name, keep the internal marker stable and treat names as display metadata or aliases.

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
        Relevant Memory OS Context:
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

public struct AgentPersonContextSection: Sendable, Equatable {
    public var references: [PersonReference]

    public init?(references: [PersonReference]) {
        let uniqueReferences = Self.uniqueReferences(references)
        guard !uniqueReferences.isEmpty else { return nil }
        self.references = uniqueReferences
    }

    public var renderedText: String {
        var lines: [String] = [
            "Referenced People in Current User Request:",
            "These are explicit people selected by the user in Composer. Treat them as typed Person references, not plain names.",
            "Use person_id when calling Person Registry tools or attributing person-related memory. Do not infer a different person from display_name unless this reference is invalid."
        ]
        for reference in references {
            lines.append("- mention: \(reference.mentionText)")
            lines.append("  type: person")
            lines.append("  person_id: \(reference.personID.rawValue)")
            lines.append("  display_name: \(reference.displayName)")
            if let status = reference.status {
                lines.append("  status: \(status.rawValue)")
            }
            if let mergedIntoID = reference.mergedIntoID {
                lines.append("  merged_into_person_id: \(mergedIntoID.rawValue)")
            }
            if let memoryEntityID = reference.memoryEntityID {
                lines.append("  memory_entity_id: \(memoryEntityID)")
            }
            if let memoryStableKey = reference.memoryStableKey {
                lines.append("  memory_stable_key: \(memoryStableKey)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func uniqueReferences(_ references: [PersonReference]) -> [PersonReference] {
        var seen = Set<ContactID>()
        var result: [PersonReference] = []
        for reference in references {
            guard !seen.contains(reference.personID) else { continue }
            seen.insert(reference.personID)
            result.append(reference)
        }
        return result
    }
}

public struct AgentPromptAssembly: Sendable, Equatable {
    public var instruction: AgentInstructionSection
    public var memory: AgentMemorySection?
    public var conversation: AgentConversationSection
    public var userRequest: AgentUserRequestSection
    public var personContext: AgentPersonContextSection?
    public var attachmentContext: AgentAttachmentContextSection?
    public var diagnostics: AgentPromptDiagnostics

    public init(
        instruction: AgentInstructionSection = AgentInstructionSection(),
        memory: AgentMemorySection? = nil,
        conversation: AgentConversationSection,
        userRequest: AgentUserRequestSection,
        personContext: AgentPersonContextSection? = nil,
        attachmentContext: AgentAttachmentContextSection? = nil,
        diagnostics: AgentPromptDiagnostics = AgentPromptDiagnostics(projectionMode: .legacySingleUserMessage)
    ) {
        self.instruction = instruction
        self.memory = memory
        self.conversation = conversation
        self.userRequest = userRequest
        self.personContext = personContext
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
            personContext: AgentPersonContextSection(references: request.personReferences),
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
        if let personContext = assembly.personContext {
            append(
                id: "person_context",
                title: "Referenced people",
                role: "user",
                text: personContext.renderedText,
                notes: ["explicit composer person references", "count=\(personContext.references.count)", "not trimmed"]
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
            + (transformed.personContext.map { estimator.estimate($0.renderedText).estimatedTokenCount } ?? 0)
            + estimator.estimate(transformed.userRequest.text).estimatedTokenCount
        let conversationBudget = max(256, maxEstimatedTokens - fixedTokenEstimate)
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
        if let personContext = transformed.personContext {
            let result = deduplicateText(personContext.renderedText, seenFingerprints: &seenFingerprints)
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
            let userPrompt = [assembly.attachmentContext?.renderedText, assembly.personContext?.renderedText, assembly.userRequest.text]
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
            if let personContext = assembly.personContext {
                let personText = personContext.renderedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !personText.isEmpty {
                    messages.append(AgentModelMessage(role: .user, content: personText))
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
