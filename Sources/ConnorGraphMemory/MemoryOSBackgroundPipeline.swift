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
        You are performing Connor Memory OS L1 unified projection.

        Layer semantics:
        - L0: Immutable provenance vault. Raw evidence objects and spans are preserved permanently and never deleted.
        - L1: Cache buffer. Accumulates user interactions, data-source events, and other raw inputs. L1 exists because processing each message individually loses cross-message context, while accumulating without processing loses timeliness. When the cache reaches its threshold (≥100 pending events or ≥24 hours since oldest pending event), a unified L2/L3/L4 update is triggered. After a successful update, the processed L1 events are cleared. L0 retains the original evidence.
        - L2: Entity-centered operational working memory. Stores entities with aliases, types, summaries, and append-only statements.
        - L3: Reusable cross-session knowledge: theories, frameworks, standards, SOPs, decision bases, and durable cognitive structures.
        - L4: Stable entity/concept graph with controlled entity types and typed entity-to-entity relations.

        Trigger and lifecycle:
        - L1 events accumulate from chat messages, browser selections, native-source events (Mail/RSS/Calendar), and attachments.
        - Processing triggers when: pending count ≥ 100, OR oldest pending event age ≥ 24 hours.
        - Each trigger produces one L1 unified projection job. Events are batched by time proximity and token limits (≤30 events, ≤12k tokens per batch).
        - After successful artifact acceptance and projection, the processed L1 events are physically deleted. L0 remains as permanent evidence.
        - If the artifact is rejected or the job fails, L1 events are preserved for retry (up to 3 attempts) or dead-letter review.

        Goal:
        - From the cached L1 events, extract information and produce a structured MemoryOSL1UnifiedProjectionOutput artifact that will be projected into L2, L3, and L4.
        - L2: Extract entity-centered operational facts and statements from the evidence.
        - Produce L3 reusable knowledge candidates only when all four promotion filters pass (signal_quality, reuse_scope, novelty, structurability).
        - L4: Produce stable entities, concept entities, and durable relations when entity identity or concept structure is clear.
        - Ignore noise, duplicates, transient wording and unsupported guesses.
        - You must search existing L2 entity-centered working memory before deciding whether an entity or statement is new, duplicate or a refinement.
        - You must search existing L3/L4 before emitting any L3 knowledge candidate, L4 stable entity, L4 concept entity, or L4 durable relation.
        - You must record search/judgment rationale in metadata or promotionDecisions: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        - If raw L0 material is needed, request the referenced provenance object or span instead of guessing.
        - Output only MemoryOSL1UnifiedProjectionOutput JSON.

        L2 semantic anchor model:
        - L2 storage is entity-centered, but extraction must be fact-first.
        - A L2 entity is any future-useful semantic anchor for operational memory, not only a physical object.
        - L2 entities may include current_user, person_object, work_object, life_object, event, place, artifact, document, concept, metric, time_expression, task topic, decision topic, project phase, implementation component, environment/config object, or another retrievable anchor.
        - Create or update an entity only when it is likely to be searched or used as an anchor in future retrieval.
        - Do not create an entity merely because a noun phrase appears in the text.

        Direct classified fact extraction method:
        - Use fact-first, entity-second extraction.
        - For each L1 event, first identify future-useful operational facts that will help future retrieval, personalization, task continuation, project continuity, decision recall, implementation continuation, environment recovery, or relationship reasoning.
        - Drop noise, filler, transient wording, generic acknowledgements, unsupported inference, and incidental noun phrases.
        - Classify each retained fact into exactly one metadata.l2_fact_type before creating entities or statements.
        - Choose the minimal useful subject entity anchor for each retained fact.
        - Create or update only entities that are likely future retrieval anchors.
        - Write one complete natural-language statement per fact; statement text is the semantic authority.
        - Predicate/relation is a routing and retrieval handle, not the full semantics.
        - Choose the most precise GraphPredicate when clear; use RELATED_TO when useful but uncertain.
        - Preserve negation, exclusion, rejection, cancellation, postponement, and supersession directly in the statement text when applicable.
        - If a new fact refines an old fact, append a refinement statement rather than overwriting history.
        - If identity, ownership, time, or object boundary is ambiguous, mark ambiguity in metadata/warnings instead of guessing.

        Minimum entity principle:
        - Create or update the fewest entities needed to preserve the operational fact.
        - A good L2 entity is a future retrieval anchor.
        - A bad L2 entity is merely a noun phrase from the current text.
        - Prefer attaching a statement to an existing broader anchor over creating a narrow temporary entity, unless the narrow entity represents a meaningful phase, document, event, task, metric, decision topic, implementation component, or config object.

        Current user and person boundary:
        - The current user is the human operating this Connor installation/session and is semantically a person_object, but it is a protected identity anchor with special extraction/write rules.
        - Represent the current user through metadata.identity_anchor = current_user when current-user identity is needed, not through generic natural-language words.
        - Treat first-person references from user-authored chat/session evidence (I, me, my, 我, 我的) as the current user when source metadata supports that authorship.
        - Do not create separate entities named "user", "用户", "当前用户", "profile", "me", "I", or similar generic words.
        - Do not add generic aliases such as user, 用户, 当前用户, profile, current, me, or I to the current_user anchor.
        - Do not treat generic words such as user, users, 用户, 当前用户, profile, or generic Foundation KG/Wikidata user concepts as the current user.
        - Do not treat assistant-authored assumptions, suggestions, interpretations, or guesses as current-user facts unless the user explicitly confirms them.
        - Other named or described people are other_person entities, not the current user.
        - Contacts, mail senders/recipients, calendar attendees/organizers, project contributors, decision owners, and people mentioned by name/nickname/role are person identity signals. Use available contact_id, email, message sender/recipient, attendee, organization, project, and role metadata as disambiguation evidence.
        - Do not merge other people into the current user.
        - Do not assign another person's preferences, habits, goals, traits, location, family, relationships or commitments to the current user unless explicitly supported by evidence.
        - If person identity is ambiguous, preserve the ambiguity in metadata/warnings with metadata.person_role = ambiguous_person and metadata.person_resolution = needs_confirmation instead of guessing, merging, or creating a stable person entity.

        Person feature extraction policy:
        - Extract explicitly evidenced current-user and other-person features when they are useful future operational memory: preference, dislike, habit, goal, stable_trait, communication_preference, knowledge_background, emotional_support_preference, interaction_guidance, personal_context, relationship_context, constraint.
        - Inside MemoryOSL1UnifiedProjectionOutput, current-user profile_preference statements must include metadata.l2_fact_type = profile_preference, metadata.person_role = current_user, metadata.person_resolution = resolved, metadata.identity_anchor = current_user, and metadata.profile_dimension.
        - metadata.profile_dimension is an internal validation/routing key. If no specific profile dimension is available, use fact_statement.
        - Add metadata.evidence_quality and metadata.stability when naturally available, but do not invent them.
        - This metadata requirement is for this L1 artifact only. Do not ask external write tools to provide metadata.
        - For other-person profile facts, set metadata.person_role = other_person and include the strongest available identity evidence such as contact_id, normalized_email, source_message_id, organization, project, role, or name_context.
        - Weak one-off observations, jokes, transient emotions, and assistant guesses should remain low-confidence operational observations; do not write them as stable traits.
        - Do not infer medical, psychological, or sensitive identity diagnoses. Record only evidence-backed operational facts and mark sensitive facts with metadata.sensitivity.

        L1 unified output contract:
        - Output schema is MemoryOSL1UnifiedProjectionOutput JSON with operationalEntities, operationalStatements, evidenceSpans, knowledgeCandidates, conceptEntities, conceptRelations, promotionDecisions, warnings, confidence and metadata.
        - operationalEntities and operationalStatements form the L2 extraction shape: entity-centered operational memory that will be projected into L2 storage.
        - knowledgeCandidates are L3 candidates and must pass all four promotion filters before inclusion.
        - conceptEntities and conceptRelations are the L4 stable concept/entity graph section that will be projected into L4 storage.
        - Each operational statement must use a predicate from the allowed GraphPredicate raw values below.
        - Each operational statement should be a complete natural-language memory claim; statement text is the semantic authority, while predicates are retrieval/routing handles.
        - Use statement metadata to preserve extraction discipline and downstream routing.
        - Required statement metadata keys when applicable: metadata.l2_fact_type, metadata.capture_event_ids, metadata.provenance_object_ids, metadata.span_ids.
        - For person/profile facts, also set metadata.person_role to current_user, other_person, or ambiguous_person; set metadata.person_resolution to resolved, ambiguous, or needs_confirmation when applicable.
        - metadata.capture_event_ids, metadata.provenance_object_ids and metadata.span_ids should be comma-separated stable ids when multiple inputs support the same consolidated fact.
        - knowledgeCandidates may include evidenceStatementIDs for artifact-level validation and promotion judgment, but L3 storage will only persist claim as statement, discipline domain, related L4 concept names/aliases, created_at and updated_at.
        - Do not ask LLM tools to provide evidence, supportQuote, source IDs, span IDs, model IDs, schema names, artifact types, processing run IDs, entity IDs, or statement IDs for L2 updates.

        Allowed L2 assertion_kind values:
        - observed: directly stated or directly observed in the L1 event / L0 evidence.
        - inferred: a narrow operational inference that is strongly entailed by the evidence; use sparingly and explain in metadata.
        - summarized: a compact operational summary of multiple evidence-backed facts; do not use for theories or reusable knowledge.

        Allowed L2 predicates / GraphPredicate raw values:
        \(Self.allowedPredicateGuide())

        \(MemoryOSL4RelationPromptGuide.render())

        L2 entity tool contract:
        - Use memory_os_context(query) to search existing L2/L3/L4 memory before deciding whether facts are new, duplicate, or refinements. Its relation cards reveal graph context that keyword search cannot provide.
        - Use memory_os_l2_find_entities(names) to check existing L2 entities by exact name/alias. Provide likely aliases in one string separated by comma, Chinese comma, dunhao, semicolon, or newline.
        - Use memory_os_read_provenance(provenanceObjectID, spanID) when exact raw evidence from L0 is required.
        - In this L1 projection artifact, you produce the structured output directly (not via tool calls). The output artifact will be projected into L2/L3/L4 storage by the projection service.
        - Do not create entities for every noun phrase; create or update only objects likely to be useful future retrieval anchors.
        - Preserve negative or exclusion semantics directly in the statement text.

        Current-user fact handling in this L1 artifact:
        - In this L1 projection, current-user facts are encoded as operationalStatements with the current_user identity anchor (see Current user and person boundary above).
        - In real-time conversation, the dedicated memory_os_update_current_user_profile tool handles current-user anchoring, metadata construction, timestamps, and projection details automatically.
        - For general L2 entity memory in this artifact (non-current-user anchors, work objects, events, documents, implementation facts), produce operationalEntities and operationalStatements as usual.

        L2 fact taxonomy:
        - profile_preference: current-user profile facts and explicitly evidenced person profile facts, including preference, dislike, habit, goal, stable trait, stable personal context, knowledge background, communication preference, or personalized operating preference.
        - project_state: current project/work-object state, milestone, scope, requirement, constraint, design direction, or active decision context.
        - task_commitment: task, TODO, commitment, responsibility, due date, reminder, follow-up, assignment, completion or postponement.
        - calendar_time: calendar event, schedule, time block, deadline, conflict, occurrence time, start/end time or temporal coordination fact.
        - communication: mail/message/RSS/chat communication fact: sender, recipient, mention, request, reply, topic or communication-derived action.
        - source_document: fact about an attachment, document, web page, source item, transcript, citation, answer, provenance relation or evidence source.
        - decision: explicit decision, rationale, selected option, supersession, approval, rejection or decision owner.
        - implementation: code, architecture, runtime behavior, dependency, module relation, test result, bug, fix, feature or implementation status.
        - environment_config: local environment, branch, toolchain, credentials boundary, config, permission mode, workspace, OS/runtime version or deployment fact.
        - relationship: relationship between people, projects, organizations, concepts, locations, artifacts or work objects.
        - other: only when none of the above fit; explain why in metadata.

        L2 taxonomy rules:
        - Always set metadata.l2_fact_type to exactly one taxonomy value.
        - Prefer the most specific taxonomy value over other.
        - If a fact could fit multiple categories, choose the category that best describes why the fact will be retrieved later.
        - The taxonomy is for L2 operational routing only; it is not a reason to promote a fact into L3.

        Class-specific extraction cues:
        - profile_preference: Extract when evidence states or strongly shows a person's preference, dislike, habit, goal, stable trait, communication preference, interaction guidance, knowledge background, emotional-support preference, personal constraint, or stable personal context. Anchor first-person user-authored evidence to current_user only when authorship is supported. Anchor other-person profile facts only when identity is resolved. Do not extract transient moods, jokes, weak one-off observations, politeness, or assistant psychological guesses as stable profile facts.
        - project_state: Extract when evidence updates the current state, scope, milestone, requirement, constraint, design direction, active context, open problem, or known limitation of a work_object. Anchor to the most specific work_object or project phase. Prefer project_state over implementation when the fact is about product/project direction rather than code/runtime behavior.
        - task_commitment: Extract when someone commits to do something, asks for follow-up, creates a TODO, assigns responsibility, sets a due date, completes, cancels, or postpones work. Anchor to the responsible person or relevant work_object depending on retrieval need.
        - calendar_time: Extract when evidence contains a schedule, event time, deadline, time block, conflict, start/end time, recurrence, or temporal coordination. Anchor to the event or time_expression. Do not confuse vague narrative time with actionable calendar/time memory.
        - communication: Extract when evidence is about a message, email, chat, RSS item, sender, recipient, mention, request, reply, topic, or communication-derived action. Anchor to the message/document/person/work_object most likely to be searched later. Preserve sender/recipient/topic metadata when available.
        - source_document: Extract when evidence describes an attachment, document, webpage, transcript, citation, source item, answer, or provenance relationship. Anchor to the document/artifact/source item. Do not duplicate full source content; L0 remains the evidence store.
        - decision: Extract when evidence states a selected option, explicit decision, rejection, approval, rationale, owner, supersession, or tradeoff conclusion. Anchor to the work_object, person, event, or decision topic. Always preserve negative decisions and rejected options in the statement text when operationally important.
        - implementation: Extract when evidence concerns code, architecture, runtime behavior, dependency, module relation, bug, fix, feature, test result, migration, API contract, or implementation status. Anchor to the work_object, module, file, component, feature, or repository. Prefer implementation over project_state when the fact is about actual code/runtime/test behavior.
        - environment_config: Extract when evidence concerns local environment, branch, toolchain, credential boundary, config, permission mode, workspace path, OS/runtime version, deployment fact, or command environment. Anchor to the environment, work_object, repository, or config object. Drop ephemeral command output unless it changes future operation.
        - relationship: Extract when evidence establishes or updates a relation between people, projects, organizations, concepts, locations, documents, artifacts, events, or work_objects. Anchor to the relation's most retrievable subject. Use a precise predicate when available; otherwise RELATED_TO.
        - other: Use only when the fact is future-useful operational memory and no other category fits. Explain why in metadata.other_reason.

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
        - Current-user preferences, habits, goals, stable traits, constraints, emotional-support preferences, communication preferences, interaction guidance and knowledge background are L2 profile_preference facts unless they encode reusable knowledge.
        - Other-person profile facts may also be L2 profile_preference or relationship facts, but must be clearly marked as other_person and identity-resolved with evidence.
        - Ambiguous people must be marked ambiguous_person / needs_confirmation and should not produce stable L4 person entities.
        - Do not promote ordinary person profile facts into L3 merely because confidence is high.
        - Append refined profile facts; do not overwrite older profile facts in the projection artifact.

        L3 promotion filters:
        - signal_quality: pass only if the material is substantial knowledge rather than noise, style, or a one-off detail.
        - reuse_scope: pass only if the material will be reusable across future sessions, tasks, projects or decisions.
        - novelty: pass only if the material is new or materially enriches existing L3/L4 memory.
        - structurability: pass only if it can be written as one complete reusable knowledge statement, assigned exactly one discipline domain, and optionally associated with durable L4 concept entity names or aliases.
        - All four filters must pass before emitting a knowledgeCandidate.
        - promotionDecisions must record signal_quality, reuse_scope, novelty, structurability, accepted/rejected reasons, evidence ids, searched layers, duplicate/novelty judgment, and reused entity/concept ids when applicable.
        - Do not promote ordinary operational facts into L3.
        - Do not promote personal preferences, one-off tasks, calendar facts, transient environment details or implementation status into L3 unless they encode a reusable rule, standard, framework, process, or decision basis.

        L3 discipline domain rules:
        - Every accepted knowledgeCandidate must include a non-empty domain.
        - Domain means discipline classification / subject classification.
        - Domain is not a topic, title, category, tag, work object, project name, product name, module name, person name, entity name, or object alias.
        - Use lowercase kebab-case.
        - Prefer stable discipline names such as software-engineering, computer-science, artificial-intelligence, information-systems, knowledge-management, psychology, cognitive-science, economics, management, sociology, political-science, education, linguistics, philosophy, design, finance, health-sciences, humanities, social-sciences, natural-sciences, engineering-and-technology, general-knowledge.
        - Before emitting L3 knowledge candidates, use memory_os_l3_list_domains when available to inspect current L3 discipline domains and reuse an existing discipline domain when it fits.
        - Use general-knowledge only when no meaningful discipline can be determined; explain why in promotionDecisions.metadata.domain_reason.

        L3 related object names rules:
        - related_object_names is a comma-separated list of durable L4 concept entity names or aliases.
        - It must not contain project names, product names, module names, file names, people names, session IDs, temporary work objects, local environment objects, one-off task names, or ordinary L2 operational anchors.
        - Use related_object_names only when the named concept is stable enough to belong to L4 as a concept entity.
        - Prefer canonical L4 concept names when known; aliases are allowed only when they are established concept aliases.
        - Store related concept names in knowledgeCandidates.metadata.related_object_names.
        - Do not use related_object_names as tags, evidence references, or separate related entity arrays for L3 storage.

        Stable L4 entity rules:
        - Create or reuse L4 stable entities for people, organizations, projects/work objects, products, locations, durable documents/artifacts, and durable concepts/frameworks/standards.
        - The current user may be represented only through the protected stable_key current_user / metadata.person_role = current_user identity anchor. Do not add aliases such as user, 用户, 当前用户, profile, or current to this entity.
        - Named collaborators, contacts, family members and other durable people may be represented as stable person entities with metadata.person_role = other_person when identity evidence is sufficient.
        - Do not create or merge stable person entities when identity is ambiguous; emit warnings or ambiguous metadata instead.
        - Create conceptEntities only when the concept has a stable name, useful summary, clear type, and future retrieval value.
        - Create conceptRelations only when the relation is durable and useful for reasoning or retrieval.
        - conceptRelations use subjectName and objectName to reference conceptEntities by name. Do not invent IDs or local references. Entity names within one extraction must be unique.
        - Do not create L4 entities for vague temporary phrases, one-off tasks, ephemeral UI wording, unsupported inferred categories, or purely stylistic wording.

        Workflow:
        1. Read L1 events in chronological order. Each event contains a capture_event_id, event_type, source_kind, occurred_at, provenance_object_id, span_id, title, content_preview, token_estimate, and metadata.
        2. For each event, extract candidate operational facts using the direct classified fact extraction method: identify future-useful facts before creating entities.
        3. Drop noise, transient wording, unsupported guesses, and purely stylistic duplicates.
        4. Classify each retained fact into exactly one metadata.l2_fact_type.
        5. Select the minimal useful entity anchor for each retained fact.
        6. Write complete statement text and choose the most precise allowed relation/predicate.
        7. Consolidate duplicate operational facts across events while preserving useful entity names, aliases, statement text, and original wording.
        8. If a fact refines an existing L2 fact, emit append-only refinement material rather than overwriting history.
        9. L2 does not require evidence spans; keep provenance identifiers only as optional internal metadata when already available from L1/L0.
        10. Choose the most precise allowed predicate and the most appropriate metadata.l2_fact_type for every operational statement.
        11. Use `memory_os_context` to search existing L2/L3/L4 memory before deciding whether facts are new, duplicate, or refinements. Its relation cards reveal graph context that keyword search cannot provide.

        11a. Graph-Assisted Entity Resolution: When searching for existing entities, use the relation cards from `memory_os_context` to disambiguate. Two entities with similar names can be distinguished by their graph connections (e.g., "AgentOS" as a project vs "AgentOS" as a concept are differentiated by INSTANCE_OF vs SUBCLASS_OF relations). If L4 shows "AgentOS project INSTANCE_OF personal AI platform" and new evidence mentions "a personal AI platform called AgentOS", this is the SAME entity despite different wording — reuse it.

        12. Separately evaluate whether any extracted material qualifies as L3 reusable knowledge using all four promotion filters (signal_quality, reuse_scope, novelty, structurability). Before accepting a knowledge candidate, check whether L4 graph relations already imply it: if "Framework X APPLIES_TO Domain Y" and "Domain Y STUDIED_BY Method Z" already exist, a candidate claiming "Framework X is relevant to Method Z" is implicit — flag it as a possible duplicate and explain in promotionDecisions. For accepted candidates, write a complete claim, choose exactly one non-empty discipline domain, optionally provide metadata.related_object_names containing durable L4 concept entity names or aliases, and record domain reasoning in promotionDecisions.

        13. Separately evaluate whether any stable L4 entity, concept entity, or durable relation should be emitted, reused, or rejected. When creating conceptRelations, prioritize cross-domain connections that bridge previously separate graph clusters. If A→B→C already exists, a new direct A→C relation has less value than a relation connecting two unrelated branches. Record the search-backed judgment in metadata or promotionDecisions.

        14. Do not produce unsupported guesses, broad conclusions without evidence, or knowledge/entity records that fail the rules above.

        After this artifact is accepted and projected into L2/L3/L4, the processed L1 events will be cleared. L0 retains the original evidence permanently.

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
            description: "Expand a Memory OS L4 stable entity or concept by depth-limited graph traversal.",
            inputSchemaJSON: "{\"entityID\":\"string\",\"depth\":\"number\",\"limit\":\"number\"}",
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
            inputSchemaJSON: "{\"entities\":[{\"name\":\"string\",\"type?\":\"string\",\"aliases?\":\"string\",\"summary?\":\"string\",\"statements\":[{\"text\":\"string\",\"relation?\":\"GraphPredicate\",\"factType?\":\"string\"}]}]}",
            usagePolicy: "Use for general L2 entity writes (non-current-user). Search memory_os_context first to check for existing entities. Use for work objects, people, events, documents, implementation facts, relationships."
        )
    }

    private static func updateCurrentUserProfileTool() -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_update_current_user_profile",
            description: "Write current-user-scoped L2 fact statements. Automatically handles current_user anchor, timestamps, and projection.",
            inputSchemaJSON: "{\"facts\":[{\"statement\":\"string\",\"factType\":\"string\",\"relation\":\"GraphPredicate\"}]}",
            usagePolicy: "MANDATORY for current-user facts. When evidence identifies the human operator (first-person references with source support), use this tool instead of memory_os_l2_update_entities. Only provide statement, factType, and relation."
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

        \(MemoryOSBackgroundToolCatalog.promptSection(for: tools, stage: "L1 unified projection"))

        Stage-specific tool policy:
        - Prefer the provided L1 packet first. It contains the cached events that triggered this projection job.
        - Use memory_os_read_provenance when exact raw evidence from L0 is required.
        - Use memory_os_context (via memory_os_search) before deciding whether emitted L2 facts are new, duplicates, or refinements.
        - Use memory_os_context across L3/L4 before emitting or rejecting L3 knowledge candidates, L4 stable entities, L4 concept entities, or L4 durable relations.
        - Record search-backed judgment in metadata or promotionDecisions: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        - Use memory_os_expand_l4 for entity identity ambiguity, duplicate concept detection, or relation context.

        After this artifact is accepted and projected, the processed L1 capture events will be physically deleted (L0 retains permanent evidence).

        Job contract:
        - job_id: \(draft.id)
        - capture_event_ids: \(draft.captureEventIDs.joined(separator: ","))
        - provenance_object_ids: \(draft.provenanceObjectIDs.joined(separator: ","))
        - source_span_ids: \(draft.sourceSpanIDs.joined(separator: ","))
        - output_schema: \(draft.schemaName)
        - semantic boundary: produce L2 operational facts, conservative L3 reusable knowledge candidates, and stable L4 entity/concept projections under evidence and promotion-policy constraints.
        """
    }

}
