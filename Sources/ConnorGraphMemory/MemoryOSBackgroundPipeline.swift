import Foundation
import ConnorGraphCore

public enum MemoryOSBackgroundJobKind: String, Sendable, Codable, Equatable, CaseIterable {
    case l1SynthesizeKnowledge = "memory.l1.synthesize_knowledge"
    case l1UnifiedProjection = "memory.l1.unified_projection"

    public static var l1ExecutableRawValues: [String] {
        [Self.l1SynthesizeKnowledge.rawValue, Self.l1UnifiedProjection.rawValue]
    }

    public static func isL1KnowledgeKind(_ rawValue: String) -> Bool {
        l1ExecutableRawValues.contains(rawValue)
    }
}

public enum MemoryOSTriggerReason: String, Sendable, Codable, Equatable, CaseIterable {
    case pendingCountThreshold = "pending_count_threshold"
    case pendingAgeThreshold = "pending_age_threshold"
}

public struct MemoryOSL1ProcessingTriggerPolicy: Sendable, Codable, Equatable {
    public var minPendingCount: Int
    public var maxEventsPerBlock: Int
    public var maxTokensPerBlock: Int
    public var maxPendingAge: TimeInterval?

    public init(minPendingCount: Int = 100, maxEventsPerBlock: Int = 30, maxTokensPerBlock: Int = 12_000, maxPendingAge: TimeInterval? = 24 * 60 * 60) {
        self.minPendingCount = minPendingCount
        self.maxEventsPerBlock = maxEventsPerBlock
        self.maxTokensPerBlock = maxTokensPerBlock
        self.maxPendingAge = maxPendingAge
    }

    public func triggerReason(events: [MemoryOSCaptureEvent], now: Date = Date()) -> MemoryOSTriggerReason? {
        let pending = events.filter { $0.processingState == .pending }
        guard !pending.isEmpty else { return nil }
        if pending.count >= minPendingCount { return .pendingCountThreshold }
        if let maxPendingAge, let oldest = pending.map(\.occurredAt).min(), now.timeIntervalSince(oldest) >= maxPendingAge { return .pendingAgeThreshold }
        return nil
    }

    public func shouldTrigger(events: [MemoryOSCaptureEvent], now: Date = Date()) -> Bool {
        triggerReason(events: events, now: now) != nil
    }
}

public struct MemoryOSL1UnifiedProjectionJobDraft: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var captureEventIDs: [String]
    public var provenanceObjectIDs: [String]
    public var sourceSpanIDs: [String]
    public var schemaName: String
    public var prompt: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: String = MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, captureEventIDs: [String], provenanceObjectIDs: [String], sourceSpanIDs: [String], schemaName: String = "MemoryOSL1UnifiedProjectionOutput", prompt: String, createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.captureEventIDs = captureEventIDs
        self.provenanceObjectIDs = provenanceObjectIDs
        self.sourceSpanIDs = sourceSpanIDs
        self.schemaName = schemaName
        self.prompt = prompt
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public enum MemoryOSKnowledgeJobSource: String, Sendable, Codable, Equatable, CaseIterable {
    case l1CaptureEvents = "l1_capture_events"
}

public struct MemoryOSKnowledgeSynthesisJobDraft: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var source: MemoryOSKnowledgeJobSource
    public var schemaName: String
    public var artifactType: String
    public var prompt: String
    public var sourceRecordIDs: [String]
    public var evidenceSpanIDs: [String]
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String, kind: String, source: MemoryOSKnowledgeJobSource, schemaName: String, artifactType: String, prompt: String, sourceRecordIDs: [String], evidenceSpanIDs: [String], createdAt: Date, metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.source = source
        self.schemaName = schemaName
        self.artifactType = artifactType
        self.prompt = prompt
        self.sourceRecordIDs = sourceRecordIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.createdAt = createdAt
        self.metadata = metadata
    }

    public init(l1 draft: MemoryOSL1UnifiedProjectionJobDraft) {
        self.init(id: draft.id, kind: draft.kind, source: .l1CaptureEvents, schemaName: draft.schemaName, artifactType: "memory_os_l1_unified_projection", prompt: draft.prompt, sourceRecordIDs: draft.captureEventIDs, evidenceSpanIDs: draft.sourceSpanIDs, createdAt: draft.createdAt, metadata: draft.metadata)
    }

}

private enum MemoryOSL4RelationPromptGuide {
    static func render() -> String {
        let grouped = Dictionary(grouping: MemoryOSL4RelationPredicate.allCases, by: \.category)
        let orderedCategories: [MemoryOSL4RelationCategory] = [
            .identity, .taxonomy, .composition, .dependency, .capability, .applicability,
            .provenance, .governance, .causality, .contribution, .location, .reference
        ]
        let lines = orderedCategories.compactMap { category -> String? in
            guard let predicates = grouped[category], !predicates.isEmpty else { return nil }
            return "- \(category.rawValue): " + predicates.map(\.rawValue).joined(separator: ", ")
        }
        return """
        Allowed L4 relation predicates / MemoryOSL4RelationPredicate raw values:
        \(lines.joined(separator: "\n"))

        L4 relation predicate rules:
        - For conceptRelations, use subjectName and objectName to reference conceptEntities by exact name.
        - Do not use local IDs or internal references; cross-reference by name only.
        - For conceptRelations.predicate, use only the raw values listed above.
        - Do not invent predicates. Do not output natural-language predicates such as is_a, has_a, can_do, supports, contains_part, or relates_to.
        - Map is_a to INSTANCE_OF when an entity is an instance of a type/class; map is_a to SUBCLASS_OF when a class/concept is a subtype of another class/concept; use BROADER_THAN/NARROWER_THAN for weak concept hierarchy.
        - Map has_a to HAS_PART for durable composition, CONTAINS for containment, SUPPORTS_CAPABILITY for capability, USES for tool/resource usage, or REQUIRES for necessary conditions.
        - RELATED_TO only as a last resort and include metadata.reason.
        - SAME_AS, EQUIVALENT_TO, EXACT_MATCH, CAUSES, RISKS, SUPERSEDES and DEPRECATES are high-impact identity and causality predicates; verify the relation is semantically correct before using them.
        - Ordinary attributes and literal values should remain L2 facts; do not create L4 entities or conceptRelations just to hold property values.
        """
    }
}

public struct MemoryOSL1UnifiedProjectionPromptBuilder: Sendable {
    public init() {}

    public func prompt(for events: [MemoryOSCaptureEvent]) -> String {
        let packet: [String: Any] = [
            "l1_capture_events": events.map { event in
                [
                    "capture_event_id": event.id,
                    "event_type": event.eventType,
                    "source_kind": event.metadata["source_kind"] ?? event.metadata["source"] ?? event.eventType,
                    "occurred_at": Self.iso8601(event.occurredAt),
                    "provenance_object_id": event.provenanceObjectID,
                    "span_id": event.metadata["span_id"] ?? "",
                    "title": event.metadata["title"] ?? "",
                    "content_preview": event.metadata["content_preview"] ?? event.metadata["preview"] ?? "",
                    "token_estimate": event.tokenEstimate,
                    "metadata": event.metadata
                ] as [String: Any]
            }
        ]
        return """
        You are processing Connor Memory OS L1 cached events. Read the events, extract useful information, and directly write to L2/L3/L4 using the provided tools.

        Layer semantics:
        - L0: Immutable provenance vault. Raw evidence objects and spans are preserved permanently and never deleted.
        - L1: Cache buffer. Accumulates user interactions, data-source events, and other raw inputs. When the cache reaches its threshold (≥100 pending events or ≥24 hours since oldest pending event), this processing job is triggered. After successful processing, the processed L1 events are cleared. L0 retains the original evidence.
        - L2: Entity-centered operational working memory. Stores entities with aliases, types, summaries, and append-only statements.
        - L3: Reusable cross-session knowledge: theories, frameworks, standards, SOPs, decision bases, and durable cognitive structures.
        - L4: Stable entity/concept graph with controlled entity types and typed entity-to-entity relations.

        Trigger and lifecycle:
        - L1 events accumulate from chat messages, browser selections, native-source events (Mail/RSS/Calendar), and attachments.
        - Processing triggers when: pending count ≥ 100, OR oldest pending event age ≥ 24 hours.
        - Events are batched by time proximity and token limits (≤30 events, ≤12k tokens per batch).
        - After successful processing, the processed L1 events are physically deleted. L0 remains as permanent evidence.
        - If processing fails, L1 events are preserved for retry (up to 3 attempts) or dead-letter review.

        Goal:
        - From the cached L1 events, extract information and directly write to L2, L3, and L4 using the provided write tools.
        - L2: Use memory_os_l2_update_entities to write L2 entity-centered working memory: operational facts and statements.
        - L2 (current user): Use memory_os_update_current_user_profile for current-user facts. This tool automatically handles anchoring, timestamps, and projection.
        - L3: Use memory_os_l3_update_beliefs to write L3 reusable knowledge candidates that pass all four promotion filters.
        - L4: Use memory_os_l4_update_entities to write L4 stable entities, concept entities, and durable relations.
        - Ignore noise, duplicates, transient wording and unsupported guesses.
        - You must search existing memory (memory_os_context) before writing to check for duplicates or refinements.
        - When you need raw evidence from data sources (email, calendar, RSS, browser history), use memory_os_search to query them directly.
        - Do not output JSON artifacts. Use the write tools directly.

        L2 semantic anchor model:
        - L2 storage is entity-centered, but extraction must be fact-first.
        - A L2 entity is any future-useful semantic anchor for operational memory, not only a physical object.
        - L2 entities may include person_object, work_object, life_object, event, place, artifact, document, concept, metric, time_expression, task topic, decision topic, project phase, implementation component, environment/config object, or another retrievable anchor.
        - Create or update an entity only when it is likely to be searched or used as an anchor in future retrieval.
        - Do not create an entity merely because a noun phrase appears in the text.

        Direct classified fact extraction method:
        - Use fact-first, entity-second extraction.
        - For each L1 event, first identify future-useful operational facts that will help future retrieval, personalization, task continuation, project continuity, decision recall, implementation continuation, environment recovery, or relationship reasoning.
        - Drop noise, filler, transient wording, generic acknowledgements, unsupported inference, and incidental noun phrases.
        - Classify each retained fact into exactly one factType before creating entities or statements.
        - Choose the minimal useful subject entity anchor for each retained fact.
        - Create or update only entities that are likely future retrieval anchors.
        - Write one complete natural-language statement per fact.
        - Choose the most precise GraphPredicate when clear; use RELATED_TO when useful but uncertain.
        - Preserve negation, exclusion, rejection, cancellation, postponement, and supersession directly in the statement text when applicable.
        - If a new fact refines an old fact, append a refinement statement rather than overwriting history.
        - If identity, ownership, time, or object boundary is ambiguous, report it as a warning instead of guessing.

        Minimum entity principle:
        - Create or update the fewest entities needed to preserve the operational fact.
        - A good L2 entity is a future retrieval anchor.
        - A bad L2 entity is merely a noun phrase from the current text.
        - Prefer attaching a statement to an existing broader anchor over creating a narrow temporary entity, unless the narrow entity represents a meaningful phase, document, event, task, metric, decision topic, implementation component, or config object.

        Current user and person boundary:
        - The current user is the human operating this Connor installation. First-person references from user-authored evidence (I, me, my, 我, 我的) indicate the current user when source metadata supports that authorship.
        - When a fact is about the current user, you MUST use memory_os_update_current_user_profile instead of memory_os_l2_update_entities. Do NOT call memory_os_context first for current-user facts — the tool handles everything automatically.
        - For current-user facts relation: Use PREFERS for preferences/interests, ABOUT for topic relations, RELATED_TO as fallback. Do NOT invent relation names like INTERESTED_IN.
        - Do not create L2 entities named "user", "用户", "当前用户", "profile", "me", "I", or similar generic words for the current user.
        - Do not treat assistant-authored assumptions, suggestions, interpretations, or guesses as current-user facts unless the user explicitly confirms them.
        - Other named or described people use memory_os_l2_update_entities, not the current_user tool.
        - If person identity is ambiguous, do not write it as a stable person entity. Report ambiguity as a warning instead.

        Person feature extraction policy:
        - Extract explicitly evidenced current-user and other-person features when they are useful future operational memory: preference, dislike, habit, goal, stable_trait, communication_preference, knowledge_background, interaction_guidance, personal_context, constraint.
        - Current-user profile_preference facts: use memory_os_update_current_user_profile with factType = profile_preference.
        - Other-person profile facts: use memory_os_l2_update_entities. Only write when identity is clearly resolved from evidence. Use SAME_AS for identity relations, NOT IDENTITY.
        - Weak one-off observations, jokes, transient emotions, and assistant guesses should not be written as stable traits.
        - Do not infer medical, psychological, or sensitive identity diagnoses.

        Allowed L2 predicates / GraphPredicate raw values:
        \(Self.allowedPredicateGuide())

        ⚠️ IMPORTANT: Only use the exact raw values listed above (e.g., SAME_AS, NOT IDENTITY). Do not invent or abbreviate relation names. If unsure, use RELATED_TO.

        \(MemoryOSL4RelationPromptGuide.render())

        Tool usage summary:
        - memory_os_context(query) — Search L2/L3/L4 before writing. Use to check for duplicates and existing context. NOT needed for current-user facts (use memory_os_update_current_user_profile directly).
        - memory_os_l2_update_entities(entities[]) — Write L2 entities and statements. Each entity needs name (required), type, aliases, summary, and statements[].
        - memory_os_update_current_user_profile(facts[]) — MANDATORY for current-user facts. Each fact needs statement, factType, and relation.
        - memory_os_l3_update_beliefs(beliefs[]) — Write L3 knowledge. Each belief needs statement (required), domain, relatedEntityNames.
        - memory_os_l4_update_entities(entities[], relations[]) — Write L4 entities and relations.
        - memory_os_search(query) — Search external data sources (email, calendar, RSS, browser history) for evidence.
        - memory_os_expand_l4(entityName, depth, limit) — Expand L4 entity graph for disambiguation. Accepts entity name; internally resolves to matching L4 entity.
        - Do not create entities for every noun phrase; create or update only objects likely to be useful future retrieval anchors.
        - Preserve negative or exclusion semantics directly in the statement text.

        L2 fact taxonomy (use as factType parameter):
        - profile_preference: preference, dislike, habit, goal, stable trait, stable personal context, knowledge background, communication preference, or personalized operating preference.
        - project_state: current project/work-object state, milestone, scope, requirement, constraint, design direction, or active decision context.
        - task_commitment: task, TODO, commitment, responsibility, due date, reminder, follow-up, assignment, completion or postponement.
        - calendar_time: calendar event, schedule, time block, deadline, conflict, occurrence time, start/end time or temporal coordination fact.
        - communication: mail/message/RSS/chat communication fact: sender, recipient, mention, request, reply, topic or communication-derived action.
        - source_document: fact about an attachment, document, web page, source item, transcript, citation, answer or evidence source.
        - decision: explicit decision, rationale, selected option, supersession, approval, rejection or decision owner.
        - implementation: code, architecture, runtime behavior, dependency, module relation, test result, bug, fix, feature or implementation status.
        - environment_config: local environment, branch, toolchain, config, permission mode, workspace, OS/runtime version or deployment fact.
        - relationship: relationship between people, projects, organizations, concepts, locations, artifacts or work objects.
        - other: only when none of the above fit.

        L2 taxonomy rules:
        - Always set factType to exactly one taxonomy value.
        - Prefer the most specific taxonomy value over other.
        - If a fact could fit multiple categories, choose the category that best describes why the fact will be retrieved later.
        - The taxonomy is for L2 operational routing only; it is not a reason to promote a fact into L3.

        Class-specific extraction cues:
        - profile_preference: Extract when evidence states or strongly shows a person's preference, dislike, habit, goal, stable trait, communication preference, interaction guidance, knowledge background, personal constraint, or stable personal context. Current-user facts → memory_os_update_current_user_profile. Other-person facts → memory_os_l2_update_entities (only when identity is resolved). Do not extract transient moods, jokes, weak one-off observations as stable facts.
        - project_state: Extract when evidence updates the current state, scope, milestone, requirement, constraint, design direction, active context, open problem, or known limitation of a work_object. Prefer project_state over implementation when the fact is about product/project direction rather than code/runtime behavior.
        - task_commitment: Extract when someone commits to do something, asks for follow-up, creates a TODO, assigns responsibility, sets a due date, completes, cancels, or postpones work.
        - calendar_time: Extract when evidence contains a schedule, event time, deadline, time block, conflict, start/end time, recurrence, or temporal coordination. Do not confuse vague narrative time with actionable calendar/time memory.
        - communication: Extract when evidence is about a message, email, chat, RSS item, sender, recipient, mention, request, reply, topic, or communication-derived action.
        - source_document: Extract when evidence describes an attachment, document, webpage, transcript, citation, source item, or answer.
        - decision: Extract when evidence states a selected option, explicit decision, rejection, approval, rationale, owner, supersession, or tradeoff conclusion. Always preserve negative decisions in the statement text when operationally important.
        - implementation: Extract when evidence concerns code, architecture, runtime behavior, dependency, module relation, bug, fix, feature, test result, migration, API contract, or implementation status. Prefer implementation over project_state when the fact is about actual code/runtime/test behavior.
        - environment_config: Extract when evidence concerns local environment, branch, toolchain, config, permission mode, workspace path, OS/runtime version, deployment fact, or command environment. Drop ephemeral command output unless it changes future operation.
        - relationship: Extract when evidence establishes or updates a relation between people, projects, organizations, concepts, locations, documents, artifacts, events, or work_objects. Use a precise predicate when available; otherwise RELATED_TO.
        - other: Use only when the fact is future-useful operational memory and no other category fits.

        Statement writing templates:
        - Preference: "{person} prefers/dislikes/has a habit/has a goal/has a constraint: {specific content}."
        - Project state: "{work_object} currently has state/scope/constraint/design direction: {specific content}."
        - Decision: "{subject} decided/approved/rejected/deferred/superseded {decision content}. Rationale: {rationale if evidenced}."
        - Task: "{person or work_object} has a task/commitment/follow-up: {action}, owner/due/status: {details if evidenced}."
        - Implementation: "{component/work_object} has implementation fact: {code/runtime/test/bug/fix/status detail}."
        - Source document: "{document/artifact} contains/describes/supports/answers: {specific content}."
        - Relationship: "{subject} is related to {object} by: {specific relationship}."
        - Avoid vague statements such as "This is important", "The user discussed X", or "There was a conversation about X" unless the conversation fact itself is the useful memory.

        Person/profile routing rules:
        - Current-user facts → memory_os_update_current_user_profile (factType = profile_preference or other appropriate type).
        - Other-person facts → memory_os_l2_update_entities. Only write when identity is clearly resolved.
        - Ambiguous people should not be written as stable person entities.
        - Do not promote ordinary person profile facts into L3 merely because confidence is high.

        L3 promotion filters (all four must pass before calling memory_os_l3_update_beliefs):
        - signal_quality: pass only if the material is substantial knowledge rather than noise, style, or a one-off detail.
        - reuse_scope: pass only if the material will be reusable across future sessions, tasks, projects or decisions.
        - novelty: pass only if the material is new or materially enriches existing L3/L4 memory.
        - structurability: pass only if it can be written as one complete reusable knowledge statement with a discipline domain.
        - Do not promote ordinary operational facts into L3.
        - Do not promote personal preferences, one-off tasks, calendar facts, transient environment details or implementation status into L3 unless they encode a reusable rule, standard, framework, process, or decision basis.

        L3 discipline domain rules:
        - Every L3 belief should include a non-empty domain.
        - Domain means discipline classification (not a topic, project name, or entity name).
        - Use lowercase kebab-case. Examples below are not exhaustive — choose the discipline that best classifies the knowledge, or create a new domain name if none fit.
        - technology: software-engineering, computer-science, artificial-intelligence, data-science, information-systems, security, networking, devops, database, distributed-systems, mobile-development, frontend, backend, compiler, operating-systems, embedded-systems, cloud-computing
        - science: mathematics, statistics, physics, chemistry, biology, medicine, neuroscience, environmental-science
        - social-science: psychology, cognitive-science, sociology, economics, political-science, linguistics, anthropology, education, journalism
        - business: management, marketing, finance, operations-research, product-management, strategy, entrepreneurship
        - engineering: electrical-engineering, mechanical-engineering, civil-engineering, aerospace-engineering
        - humanities: philosophy, history, law, ethics, creative-writing, music, art
        - interdisciplinary: knowledge-management, design, systems-thinking, complexity-science, general-knowledge
        - Use general-knowledge only when no meaningful discipline can be determined.

        L3 related entity names rules:
        - relatedEntityNames is a comma-separated list of durable L4 concept entity names.
        - It must not contain project names, product names, module names, file names, people names, or temporary work objects.
        - Use relatedEntityNames only when the named concept is stable enough to belong to L4.

        Stable L4 entity rules:
        - Create or reuse L4 stable entities for people, organizations, projects/work objects, products, locations, durable documents/artifacts, and durable concepts/frameworks/standards.
        - Create conceptEntities only when the concept has a stable name, useful summary, clear type, and future retrieval value.
        - Create conceptRelations only when the relation is durable and useful for reasoning or retrieval.
        - conceptRelations use subjectName and objectName to reference conceptEntities by name. Entity names within one call must be unique.
        - Do not create L4 entities for vague temporary phrases, one-off tasks, or ephemeral wording.

        Workflow:
        1. Read L1 events in chronological order.
        2. For each event, extract candidate operational facts using the direct classified fact extraction method.
        3. Drop noise, transient wording, unsupported guesses, and purely stylistic duplicates.
        4. Classify each retained fact into exactly one factType.
        5. Select the minimal useful entity anchor for each retained fact.
        6. Write complete statement text and choose the most precise allowed relation/predicate.
        7. Consolidate duplicate operational facts across events.
        8. If a fact refines an existing L2 fact, append a refinement statement rather than overwriting.
        9. Search memory_os_context before writing to check for duplicates and existing context. Skip for current-user facts (go directly to step 10).
        10. Current-user facts → memory_os_update_current_user_profile.
        11. Other L2 facts → memory_os_l2_update_entities.
        12. L3 knowledge (after all four promotion filters pass) → memory_os_l3_update_beliefs.
        13. L4 stable entities and relations → memory_os_l4_update_entities.
        14. When searching for existing entities, use memory_os_context relation cards to disambiguate.
        15. When evaluating L3 candidates, check whether L4 graph relations already imply the knowledge.
        16. Do not produce unsupported guesses or knowledge that fails the promotion filters.

        After processing, the L1 events will be cleared. L0 retains the original evidence permanently.

        L1 capture events are provided as an ordered JSON packet:
        \(Self.renderJSON(packet))
        """
    }

    private static func allowedPredicateGuide() -> String {
        let grouped: [(String, [GraphPredicate])] = [
            ("identity and taxonomy", [.subclassOf, .instanceOf, .aliasOf, .sameAs]),
            ("structure and dependency", [.partOf, .hasPart, .dependsOn, .relatedTo]),
            ("ownership and provenance", [.createdBy, .developedBy, .ownedBy, .locatedIn]),
            ("time and scheduling", [.occurredAt, .scheduledAt, .startsAt, .endsAt]),
            ("personal operating memory", [.prefers, .dislikes, .hasHabit, .hasGoal, .committedTo, .responsibleFor, .remindedAt, .livesAt, .knowsPerson, .familyOf]),
            ("communication", [.sentBy, .sentTo, .ccTo, .receivedAt, .about, .mentions, .requestsAction, .repliesTo]),
            ("calendar and tasks", [.attends, .organizerOf, .conflictsWith, .blocksTime, .dueAt, .assignedTo, .completedAt, .postponedTo]),
            ("knowledge/evidence relations usable as L2 facts", [.answers, .answeredBy, .derivedFrom, .supportedBy, .implements, .appliesTo, .decidedBy, .supersedes])
        ]
        return grouped.map { group, predicates in
            "- \(group): " + predicates.map(\.rawValue).joined(separator: ", ")
        }.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func renderJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}

public struct MemoryOSL1UnifiedProjectionJobPlanner: Sendable {
    public var policy: MemoryOSL1ProcessingTriggerPolicy
    public var promptBuilder: MemoryOSL1UnifiedProjectionPromptBuilder

    public init(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), promptBuilder: MemoryOSL1UnifiedProjectionPromptBuilder = MemoryOSL1UnifiedProjectionPromptBuilder()) {
        self.policy = policy
        self.promptBuilder = promptBuilder
    }

    public func planJobs(from events: [MemoryOSCaptureEvent], now: Date = Date()) -> [MemoryOSL1UnifiedProjectionJobDraft] {
        let pending = events.filter { $0.processingState == .pending }.sorted { $0.occurredAt < $1.occurredAt }
        guard let triggerReason = policy.triggerReason(events: pending, now: now) else { return [] }
        let blocks = chunkEvents(pending)
        return blocks.map { block in
            MemoryOSL1UnifiedProjectionJobDraft(
                captureEventIDs: block.map(\.id),
                provenanceObjectIDs: block.map(\.provenanceObjectID),
                sourceSpanIDs: block.compactMap { $0.metadata["span_id"] },
                prompt: promptBuilder.prompt(for: block),
                createdAt: now,
                metadata: [
                    "event_count": String(block.count),
                    "token_estimate": String(block.reduce(0) { $0 + $1.tokenEstimate }),
                    "trigger_reason": triggerReason.rawValue
                ]
            )
        }
    }

    private func chunkEvents(_ events: [MemoryOSCaptureEvent]) -> [[MemoryOSCaptureEvent]] {
        var chunks: [[MemoryOSCaptureEvent]] = []
        var current: [MemoryOSCaptureEvent] = []
        var tokens = 0
        for event in events {
            let wouldExceedCount = current.count >= policy.maxEventsPerBlock
            let wouldExceedTokens = !current.isEmpty && tokens + event.tokenEstimate > policy.maxTokensPerBlock
            if wouldExceedCount || wouldExceedTokens {
                chunks.append(current)
                current = []
                tokens = 0
            }
            current.append(event)
            tokens += event.tokenEstimate
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

public struct MemoryOSBackgroundToolDescriptor: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchemaJSON: String
    public var usagePolicy: String

    public init(name: String, description: String, inputSchemaJSON: String, usagePolicy: String) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
        self.usagePolicy = usagePolicy
    }
}

public struct MemoryOSBackgroundToolCall: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String = UUID().uuidString, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct MemoryOSBackgroundToolResult: Sendable, Codable, Equatable {
    public var callID: String
    public var name: String
    public var contentJSON: String
    public var contentText: String
    public var citations: [String]

    public init(callID: String, name: String, contentJSON: String, contentText: String = "", citations: [String] = []) {
        self.callID = callID
        self.name = name
        self.contentJSON = contentJSON
        self.contentText = contentText
        self.citations = citations
    }
}

public enum MemoryOSBackgroundToolCatalog {
    public static func l1UnifiedProjectionTools() -> [MemoryOSBackgroundToolDescriptor] {
        [
            contextTool(),
            expandL4Tool(usage: "Use memory_os_expand_l4 when L4 entity identity, duplicate concept detection, or relation context is necessary for grounded L1 processing."),
            readProvenanceTool(),
            l2UpdateEntitiesTool(),
            updateCurrentUserProfileTool(),
            l3UpdateBeliefsTool(),
            l4UpdateEntitiesTool()
        ]
    }

    public static func l2ToKnowledgeTools() -> [MemoryOSBackgroundToolDescriptor] {
        [contextTool(), expandL4Tool(usage: "Use memory_os_expand_l4 before creating concept relations or when concept identity is ambiguous."), readRecordTool(), readProvenanceTool()]
    }

    public static func promptSection(for tools: [MemoryOSBackgroundToolDescriptor], stage: String) -> String {
        let rendered = tools.map { tool in
            """
            - \(tool.name)
              Purpose: \(tool.description)
              Input schema: \(tool.inputSchemaJSON)
              Usage policy: \(tool.usagePolicy)
            """
        }.joined(separator: "\n")
        return """
        Available tools for \(stage):
        \(rendered)

        Tool-use rules:
        - Use read tools to search existing memory before writing.
        - Use write tools to directly update L2/L3/L4 memory. Do not output JSON artifacts for projection.
        - When identifying current-user facts, use memory_os_update_current_user_profile instead of memory_os_l2_update_entities.
        - Prefer `memory_os_context` for entity disambiguation and duplicate detection; its relation cards reveal graph context that keyword search cannot provide.
        - When `memory_os_context` returns entity cards with multiple incoming relations, scan them to resolve ambiguous entity names through their connections.
        """
    }

    private static func contextTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_context",
            description: "Search Connor Memory OS L2-L4 with natural-language terms and return entity cards and relation cards as a flat array. Prefer this over keyword search for entity disambiguation, duplicate detection, and cross-domain connection discovery.",
            inputSchemaJSON: "{\"query\":\"string (search terms separated by ;)\"}",
            usagePolicy: "Must use memory_os_context before deciding whether emitted L2 facts are new/refinements and before creating or reusing L3/L4 candidates. Its relation cards reveal graph context that keyword search cannot. Record duplicate/novelty judgment in metadata or promotionDecisions."
        )
    }

    private static func expandL4Tool(usage: String) -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_expand_l4",
            description: "Expand a Memory OS L4 stable entity or concept by depth-limited graph traversal. Accepts entity name (not ID) — internally resolves to the matching L4 entity.",
            inputSchemaJSON: "{\"entityName\":\"string\",\"depth\":\"number\",\"limit\":\"number\"}",
            usagePolicy: usage
        )
    }

    private static func readRecordTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_read_record",
            description: "Read a full Memory OS record from a search hit when summary-level context is insufficient.",
            inputSchemaJSON: "{\"layer\":\"L0|L1|L2|L3|L4\",\"recordID\":\"string\"}",
            usagePolicy: "Use only when summary-level context is insufficient for novelty, duplicate, grounding or concept identity decisions."
        )
    }

    private static func readProvenanceTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_read_provenance",
            description: "Read exact L0 provenance object or span content when raw evidence is required.",
            inputSchemaJSON: "{\"provenanceObjectID\":\"string\",\"spanID\":\"string|null\"}",
            usagePolicy: "Use when a prompt preview is insufficient, exact raw evidence is required, or an evidence citation needs validation."
        )
    }

    private static func l2UpdateEntitiesTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_l2_update_entities",
            description: "Write L2 entity-centered working memory. Upserts entities by name and appends statements.",
            inputSchemaJSON: "{\"entities\":[{\"name\":\"string\",\"type?\":\"string\",\"aliases?\":\"string\",\"summary?\":\"string\",\"statements\":[{\"text\":\"string\",\"relation?\":\"GraphPredicate (e.g., RELATED_TO, ABOUT, SAME_AS)\",\"factType?\":\"string\"}]}]}",
            usagePolicy: "Use for general L2 entity writes (non-current-user). Search memory_os_context first to check for existing entities. Use for work objects, people, events, documents, implementation facts, relationships. Invalid relations will fallback to RELATED_TO."
        )
    }

    private static func updateCurrentUserProfileTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_update_current_user_profile",
            description: "Write current-user-scoped L2 fact statements. Automatically handles current_user anchor, timestamps, and projection.",
            inputSchemaJSON: "{\"facts\":[{\"statement\":\"string\",\"factType\":\"string\",\"relation\":\"GraphPredicate (e.g., PREFERS, ABOUT, RELATED_TO)\"}]}",
            usagePolicy: "MANDATORY for current-user facts. When evidence identifies the human operator (first-person references with source support), use this tool instead of memory_os_l2_update_entities. Only provide statement, factType, and relation. For interests/preferences, use PREFERS. For topic relations, use ABOUT. Invalid relations will fallback to RELATED_TO."
        )
    }

    private static func l3UpdateBeliefsTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_l3_update_beliefs",
            description: "Write L3 reusable knowledge statements directly. Use for cross-session knowledge, theories, frameworks, standards, SOPs.",
            inputSchemaJSON: "{\"beliefs\":[{\"statement\":\"string\",\"domain?\":\"string\",\"relatedEntityNames?\":\"string\"}]}",
            usagePolicy: "Only write after all four promotion filters pass: signal_quality, reuse_scope, novelty, structurability. Search L3/L4 first for duplicates. Include discipline domain for each belief."
        )
    }

    private static func l4UpdateEntitiesTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_l4_update_entities",
            description: "Write L4 stable entities and typed entity-to-entity relations. Entities are upserted by name+type.",
            inputSchemaJSON: "{\"entities\":[{\"name\":\"string\",\"type?\":\"string\",\"domain?\":\"string\",\"summary?\":\"string\",\"aliases?\":\"string\"}],\"relations\":[{\"subjectName\":\"string\",\"predicate\":\"L4Predicate\",\"objectName\":\"string\",\"text?\":\"string\"}]}",
            usagePolicy: "Search L4 first to check for existing entities. Create conceptEntities only when the concept has a stable name, useful summary, clear type, and future retrieval value. Use controlled entity types."
        )
    }
}

public struct MemoryOSBackgroundModelRequest: Sendable, Codable, Equatable {
    public var jobID: String
    public var kind: String
    public var schemaName: String
    public var artifactType: String
    public var prompt: String
    public var sourceRecordIDs: [String]
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]
    public var availableTools: [MemoryOSBackgroundToolDescriptor]

    public init(jobID: String, kind: String, schemaName: String, artifactType: String, prompt: String, sourceRecordIDs: [String] = [], evidenceSpanIDs: [String] = [], metadata: [String: String] = [:], availableTools: [MemoryOSBackgroundToolDescriptor] = []) {
        self.jobID = jobID
        self.kind = kind
        self.schemaName = schemaName
        self.artifactType = artifactType
        self.prompt = prompt
        self.sourceRecordIDs = sourceRecordIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.metadata = metadata
        self.availableTools = availableTools
    }
}

public struct MemoryOSBackgroundModelResponse: Sendable, Codable, Equatable {
    public var rawArtifactJSON: String
    public var metadata: [String: String]

    public init(rawArtifactJSON: String, metadata: [String: String] = [:]) {
        self.rawArtifactJSON = rawArtifactJSON
        self.metadata = metadata
    }
}

public protocol MemoryOSBackgroundModelExecutor: Sendable {
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse
}

public struct MemoryOSBackgroundJobExecutionResult: Sendable, Codable, Equatable {
    public var jobID: String
    public var kind: String
    public var rawArtifactJSON: String
    public var schemaName: String
    public var artifactType: String
    public var metadata: [String: String]

    public init(jobID: String, kind: String, rawArtifactJSON: String, schemaName: String, artifactType: String, metadata: [String: String] = [:]) {
        self.jobID = jobID
        self.kind = kind
        self.rawArtifactJSON = rawArtifactJSON
        self.schemaName = schemaName
        self.artifactType = artifactType
        self.metadata = metadata
    }
}

public struct MemoryOSBackgroundJobWorker<Executor: MemoryOSBackgroundModelExecutor>: Sendable {
    public var executor: Executor

    public init(executor: Executor) {
        self.executor = executor
    }

    public func run(_ draft: MemoryOSL1UnifiedProjectionJobDraft) throws -> MemoryOSBackgroundJobExecutionResult {
        let artifactType = "memory_os_l1_unified_projection"
        let tools = MemoryOSBackgroundToolCatalog.l1UnifiedProjectionTools()
        let prompt = enrichedL1Prompt(draft, tools: tools)
        let request = MemoryOSBackgroundModelRequest(
            jobID: draft.id,
            kind: draft.kind,
            schemaName: draft.schemaName,
            artifactType: artifactType,
            prompt: prompt,
            sourceRecordIDs: draft.captureEventIDs,
            evidenceSpanIDs: draft.sourceSpanIDs,
            metadata: draft.metadata,
            availableTools: tools
        )
        let response = try executor.execute(request)
        return MemoryOSBackgroundJobExecutionResult(jobID: draft.id, kind: draft.kind, rawArtifactJSON: response.rawArtifactJSON, schemaName: draft.schemaName, artifactType: artifactType, metadata: draft.metadata.merging(response.metadata) { _, new in new })
    }

    private func enrichedL1Prompt(_ draft: MemoryOSL1UnifiedProjectionJobDraft, tools: [MemoryOSBackgroundToolDescriptor]) -> String {
        """
        \(draft.prompt)

        \(MemoryOSBackgroundToolCatalog.promptSection(for: tools, stage: "L1 cached event processing"))

        Stage-specific tool policy:
        - Prefer the provided L1 packet first. It contains the cached events that triggered this processing job.
        - Search memory_os_context before writing to check for duplicates, refinements, and existing graph context.
        - Use memory_os_expand_l4 for entity identity ambiguity or duplicate concept detection.
        - Use memory_os_search when you need to query external data sources (email, calendar, RSS, browser history) for supporting evidence.
        - Current-user facts: use memory_os_update_current_user_profile (mandatory for current-user identification).
        - Other L2 facts: use memory_os_l2_update_entities.
        - L3 knowledge: use memory_os_l3_update_beliefs (only after all four promotion filters pass).
        - L4 entities/relations: use memory_os_l4_update_entities.

        After processing, the L1 events will be physically deleted (L0 retains permanent evidence).

        Job contract:
        - job_id: \(draft.id)
        - capture_event_ids: \(draft.captureEventIDs.joined(separator: ","))
        - provenance_object_ids: \(draft.provenanceObjectIDs.joined(separator: ","))
        - source_span_ids: \(draft.sourceSpanIDs.joined(separator: ","))
        """
    }

}
