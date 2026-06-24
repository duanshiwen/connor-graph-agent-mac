import Foundation
import ConnorGraphCore

public enum MemoryOSBackgroundJobKind: String, Sendable, Codable, Equatable, CaseIterable {
    case l1ProcessBlockToL2 = "memory.l1.process_block_to_l2"
    case l2SynthesizeKnowledge = "memory.l2.synthesize_knowledge"
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

    public func shouldTrigger(events: [MemoryOSCaptureEvent], now: Date = Date()) -> Bool {
        let pending = events.filter { $0.processingState == .pending }
        guard !pending.isEmpty else { return false }
        if pending.count >= minPendingCount { return true }
        if let maxPendingAge, let oldest = pending.map(\.occurredAt).min(), now.timeIntervalSince(oldest) >= maxPendingAge { return true }
        return false
    }
}

public struct MemoryOSL2KnowledgeSynthesisTriggerPolicy: Sendable, Codable, Equatable {
    public var minPendingStatementCount: Int
    public var maxStatementsPerBlock: Int
    public var maxTokensPerBlock: Int
    public var maxPendingAge: TimeInterval?

    public init(minPendingStatementCount: Int = 80, maxStatementsPerBlock: Int = 30, maxTokensPerBlock: Int = 12_000, maxPendingAge: TimeInterval? = 24 * 60 * 60) {
        self.minPendingStatementCount = minPendingStatementCount
        self.maxStatementsPerBlock = maxStatementsPerBlock
        self.maxTokensPerBlock = maxTokensPerBlock
        self.maxPendingAge = maxPendingAge
    }

    public func shouldTrigger(statements: [MemoryOSStatement], now: Date = Date()) -> Bool {
        let pending = pendingStatements(from: statements)
        guard !pending.isEmpty else { return false }
        if pending.count >= minPendingStatementCount { return true }
        if let maxPendingAge, let oldest = pending.map(\.committedAt).min(), now.timeIntervalSince(oldest) >= maxPendingAge { return true }
        return false
    }

    public func pendingStatements(from statements: [MemoryOSStatement]) -> [MemoryOSStatement] {
        statements.filter { statement in
            let state = statement.metadata["processing_state"] ?? statement.metadata["knowledge_synthesis_state"]
            return state == nil || state == "pending_knowledge_synthesis" || state == "pending"
        }
    }
}

public struct MemoryOSL1ToL2JobDraft: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var captureEventIDs: [String]
    public var provenanceObjectIDs: [String]
    public var sourceSpanIDs: [String]
    public var schemaName: String
    public var prompt: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: String = MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, captureEventIDs: [String], provenanceObjectIDs: [String], sourceSpanIDs: [String], schemaName: String = "MemoryOSL1UnifiedProjectionOutput", prompt: String, createdAt: Date = Date(), metadata: [String: String] = [:]) {
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

public struct MemoryOSL2ToKnowledgeJobDraft: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var statementIDs: [String]
    public var evidenceSpanIDs: [String]
    public var schemaName: String
    public var prompt: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: String = MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue, statementIDs: [String], evidenceSpanIDs: [String], schemaName: String = "MemoryOSKnowledgeExtractionOutput", prompt: String, createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.statementIDs = statementIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.schemaName = schemaName
        self.prompt = prompt
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct MemoryOSL1ToL2PromptBuilder: Sendable {
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
        - L0 is the durable provenance layer and source of raw evidence.
        - L1 is the active processing buffer / ordered memory sequence.
        - L2 is operational facts / working memory.
        - L3 is reusable knowledge: standards, principles, frameworks, decision bases, processes and durable cognitive structures.
        - L4 is stable entities, concept entities and durable entity/concept relations.
        - A successful L1 unified projection clears the processed L1 buffer only after artifact acceptance; failures preserve L1 for retry or dead-letter review.

        Goal:
        - Produce evidence-backed L2 operational facts / working memory.
        - Produce conservative L3 reusable knowledge candidates only when all promotion filters pass.
        - Produce L4 stable entities, concept entities and durable relations when entity identity or concept structure is clear.
        - Ignore noise, duplicates, transient wording and unsupported guesses.
        - You must search existing L2 operational memory before deciding whether a fact is new, duplicate or a refinement.
        - You must search existing L3/L4 before emitting any L3 knowledge candidate, L4 stable entity, L4 concept entity, or L4 durable relation.
        - You must record search/judgment evidence in metadata or promotionDecisions: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        - If raw L0 material is needed, request the referenced provenance object or span instead of guessing.
        - Output only MemoryOSL1UnifiedProjectionOutput JSON.

        Current user and person boundary:
        - The current user is the human operating this Connor installation/session.
        - Treat first-person references from user-authored chat/session evidence (I, me, my, 我, 我的, 用户) as the current user when source metadata supports that authorship.
        - Other named or described people are other_person entities, not the current user.
        - Do not merge other people into the current user.
        - Do not assign another person's preferences, habits, goals, traits, location, family, relationships or commitments to the current user unless explicitly supported by evidence.
        - If person identity is ambiguous, preserve the ambiguity in metadata/warnings instead of guessing or merging.

        L1 unified output contract:
        - Output schema is MemoryOSL1UnifiedProjectionOutput JSON with operationalEntities, operationalStatements, evidenceSpans, knowledgeCandidates, conceptEntities, conceptRelations, promotionDecisions, warnings, confidence and metadata.
        - operationalEntities and operationalStatements are the L2 operational graph section.
        - knowledgeCandidates are L3 candidates and must pass all promotion filters.
        - conceptEntities and conceptRelations are the L4 stable concept/entity graph section.
        - Each operational statement must use a predicate from the allowed GraphPredicate raw values below.
        - Each operational statement should represent one atomic operational fact, not a broad interpretation.
        - Use statement metadata to preserve extraction discipline and downstream routing.
        - Required statement metadata keys when applicable: metadata.l2_fact_type, metadata.capture_event_ids, metadata.provenance_object_ids, metadata.span_ids.
        - For person/profile facts, also set metadata.person_role to current_user, other_person, or ambiguous_person; set metadata.person_resolution to resolved, ambiguous, or needs_confirmation when applicable.
        - metadata.capture_event_ids, metadata.provenance_object_ids and metadata.span_ids should be comma-separated stable ids when multiple inputs support the same consolidated fact.
        - L3 knowledgeCandidates.evidenceStatementIDs must reference operationalStatements local statement ids from this same artifact.
        - L3 knowledgeCandidates.evidenceSpanIDs and L4 conceptRelations.evidenceSpanIDs must reference evidenceSpans ids.

        Allowed L2 assertion_kind values:
        - observed: directly stated or directly observed in the L1 event / L0 evidence.
        - inferred: a narrow operational inference that is strongly entailed by the evidence; use sparingly and explain in metadata.
        - summarized: a compact operational summary of multiple evidence-backed facts; do not use for theories or reusable knowledge.

        Allowed L2 predicates / GraphPredicate raw values:
        \(Self.allowedPredicateGuide())

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

        Person/profile routing rules:
        - Current-user preferences, habits, goals, stable traits, communication preferences and knowledge background are L2 profile_preference facts unless they encode reusable knowledge.
        - Other-person profile facts may also be L2 profile_preference or relationship facts, but must be clearly marked as other_person.
        - Do not promote ordinary person profile facts into L3 merely because confidence is high.

        L3 promotion filters:
        - signal_quality: pass only if the material is substantial knowledge rather than noise, style, or a one-off detail.
        - reuse_scope: pass only if the material will be reusable across future sessions, tasks, projects or decisions.
        - novelty: pass only if the material is new or materially enriches existing L3/L4 memory.
        - structurability: pass only if it can be assigned category, knowledge_type, scope, domain, and related concept entities.
        - All four filters must pass before emitting a knowledgeCandidate.
        - promotionDecisions must record signal_quality, reuse_scope, novelty, structurability, accepted/rejected reasons, evidence ids, searched layers, duplicate/novelty judgment, and reused entity/concept ids when applicable.
        - Do not promote ordinary operational facts into L3.
        - Do not promote personal preferences, one-off tasks, calendar facts, transient environment details or implementation status into L3 unless they encode a reusable rule, standard, framework, process, or decision basis.

        Stable L4 entity rules:
        - Create or reuse L4 stable entities for people, organizations, projects/work objects, products, locations, durable documents/artifacts, and durable concepts/frameworks/standards.
        - The current user may be represented as a stable person entity with metadata.person_role = current_user when evidence supports it.
        - Named collaborators, contacts, family members and other durable people may be represented as stable person entities with metadata.person_role = other_person.
        - Do not create or merge stable person entities when identity is ambiguous; emit warnings or ambiguous metadata instead.
        - Create conceptEntities only when the concept has a stable name, useful summary, clear type, evidence, and future retrieval value.
        - Create conceptRelations only when the relation is durable, evidence-backed, and useful for reasoning or retrieval.
        - Do not create L4 entities for vague temporary phrases, one-off tasks, ephemeral UI wording, unsupported inferred categories, or purely stylistic wording.

        Workflow:
        1. Read L1 events in chronological order.
        2. Extract candidate operational facts per event for L2.
        3. Drop noise, transient wording, unsupported guesses and purely stylistic duplicates.
        4. Consolidate duplicate operational facts across events while preserving all evidence references.
        5. If a fact refines an existing L2 fact, emit append-only refinement material rather than overwriting history.
        6. Every emitted operational fact must cite at least one capture_event_id and at least one provenance_object_id or span_id.
        7. Choose the most precise allowed predicate and the most appropriate metadata.l2_fact_type for every operational statement.
        8. Before emitting or rejecting L3/L4 candidates, search L2/L3/L4 for related facts, existing knowledge, duplicate concepts, reusable entities and supersession context.
        9. Separately evaluate whether any extracted material qualifies as L3 reusable knowledge using all four promotion filters, and record the search-backed judgment in promotionDecisions.
        10. Separately evaluate whether any stable L4 entity, concept entity, or durable relation should be emitted, reused, or rejected, and record the search-backed judgment in metadata or promotionDecisions.
        11. Do not produce unsupported guesses, broad conclusions without evidence, or knowledge/entity records that fail the rules above.

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

public struct MemoryOSL2ToKnowledgePromptBuilder: Sendable {
    public init() {}

    public func prompt(for statements: [MemoryOSStatement]) -> String {
        let packet: [String: Any] = [
            "l2_statements": statements.map { statement in
                [
                    "statement_id": statement.id,
                    "subject_id": statement.subjectID,
                    "predicate": statement.predicate,
                    "object_id": statement.objectID ?? "",
                    "text": statement.text,
                    "assertion_kind": statement.assertionKind.rawValue,
                    "confidence": statement.confidence,
                    "valid_at": Self.iso8601(statement.validAt),
                    "committed_at": Self.iso8601(statement.committedAt),
                    "evidence_span_ids": statement.evidenceSpanIDs,
                    "source_artifact_id": statement.sourceArtifactID ?? "",
                    "metadata": statement.metadata
                ] as [String: Any]
            }
        ]
        return """
        You are synthesizing Connor Memory OS L2 operational facts into reusable L3 knowledge and L4 concept graph records.

        Layer semantics:
        - L2 is operational facts / working memory, not reusable knowledge by default.
        - L3 is reusable knowledge: theories, frameworks, standards, processes, decision bases and durable cognitive structures.
        - L4 is stable entities, concept entities and concept relations.

        Conservative review policy:
        - Most L2 facts should not become L3 knowledge.
        - High confidence alone is insufficient for L3 promotion.
        - All four filters must pass before creating an L3 knowledge candidate.
        - If any dimension fails, do not create L3.
        - If existing L3 already covers the idea, output no new L3 candidate.
        - If existing L4 already contains the concept, reuse it rather than creating a duplicate.

        Use the four knowledge filters:
        1. signal quality: is this knowledge rather than noise?
        2. reuse scope: will this be reusable in the future?
        3. novelty: is this new or a material enrichment?
        4. structurability: can it be mapped to category, knowledge type, scope, domain, work object/person and concept entities?

        Accepted knowledge candidates must include explicit AI judgment fields equivalent to:
        - signal_quality: pass/fail plus reason
        - reuse_scope: pass/fail plus reason
        - novelty: pass/fail plus reason
        - structurability: pass/fail plus reason

        You must search L2, L3 and L4 before deciding whether to produce knowledge candidates, concept entities, concept relations or refined L2 facts.
        You must record the search-backed judgment for every accepted or rejected candidate: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        Do not promote ordinary personal or operational facts into L3. If a fact should be more accurate, propose refined L2 facts as append-only follow-up material rather than overwriting history.
        Output only MemoryOSKnowledgeExtractionOutput JSON for accepted knowledge candidates and L4 concepts/relations.

        L2 statements are provided as an ordered JSON packet:
        \(Self.renderJSON(packet))
        """
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

public struct MemoryOSL1ToL2JobPlanner: Sendable {
    public var policy: MemoryOSL1ProcessingTriggerPolicy
    public var promptBuilder: MemoryOSL1ToL2PromptBuilder

    public init(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), promptBuilder: MemoryOSL1ToL2PromptBuilder = MemoryOSL1ToL2PromptBuilder()) {
        self.policy = policy
        self.promptBuilder = promptBuilder
    }

    public func planJobs(from events: [MemoryOSCaptureEvent], now: Date = Date()) -> [MemoryOSL1ToL2JobDraft] {
        let pending = events.filter { $0.processingState == .pending }.sorted { $0.occurredAt < $1.occurredAt }
        guard policy.shouldTrigger(events: pending, now: now) else { return [] }
        let blocks = chunkEvents(pending)
        return blocks.map { block in
            MemoryOSL1ToL2JobDraft(
                captureEventIDs: block.map(\.id),
                provenanceObjectIDs: block.map(\.provenanceObjectID),
                sourceSpanIDs: block.compactMap { $0.metadata["span_id"] },
                prompt: promptBuilder.prompt(for: block),
                createdAt: now,
                metadata: [
                    "event_count": String(block.count),
                    "token_estimate": String(block.reduce(0) { $0 + $1.tokenEstimate })
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

public struct MemoryOSL2ToKnowledgeJobPlanner: Sendable {
    public var policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy
    public var promptBuilder: MemoryOSL2ToKnowledgePromptBuilder

    public init(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(), promptBuilder: MemoryOSL2ToKnowledgePromptBuilder = MemoryOSL2ToKnowledgePromptBuilder()) {
        self.policy = policy
        self.promptBuilder = promptBuilder
    }

    public func planJobs(from statements: [MemoryOSStatement], now: Date = Date()) -> [MemoryOSL2ToKnowledgeJobDraft] {
        let pending = policy.pendingStatements(from: statements).sorted { $0.committedAt < $1.committedAt }
        guard policy.shouldTrigger(statements: pending, now: now) else { return [] }
        return chunkStatements(pending).map { block in
            MemoryOSL2ToKnowledgeJobDraft(
                statementIDs: block.map(\.id),
                evidenceSpanIDs: Array(Set(block.flatMap(\.evidenceSpanIDs))).sorted(),
                prompt: promptBuilder.prompt(for: block),
                createdAt: now,
                metadata: [
                    "statement_count": String(block.count),
                    "source": "l2_pending_knowledge_synthesis"
                ]
            )
        }
    }

    private func chunkStatements(_ statements: [MemoryOSStatement]) -> [[MemoryOSStatement]] {
        var chunks: [[MemoryOSStatement]] = []
        var current: [MemoryOSStatement] = []
        var tokens = 0
        for statement in statements {
            let estimate = max(1, statement.text.count / 4)
            let wouldExceedCount = current.count >= policy.maxStatementsPerBlock
            let wouldExceedTokens = !current.isEmpty && tokens + estimate > policy.maxTokensPerBlock
            if wouldExceedCount || wouldExceedTokens {
                chunks.append(current)
                current = []
                tokens = 0
            }
            current.append(statement)
            tokens += estimate
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
    public static func l1ToL2Tools() -> [MemoryOSBackgroundToolDescriptor] {
        [searchTool(layers: ["L2", "L3", "L4"], usage: "Must use memory_os_search before deciding whether emitted L2 facts are new/refinements and before creating or reusing L3/L4 candidates; record duplicate/novelty judgment in metadata or promotionDecisions."), readProvenanceTool(), expandL4Tool(usage: "Use memory_os_expand_l4 when L4 entity identity, duplicate concept detection, or relation context is necessary for grounded L1 projection.")]
    }

    public static func l2ToKnowledgeTools() -> [MemoryOSBackgroundToolDescriptor] {
        [searchTool(layers: ["L2", "L3", "L4"], usage: "Must search L2, L3 and L4 before creating, reusing or rejecting L3 knowledge, L4 concepts, concept relations, or refined L2 facts; record duplicate/novelty judgment and reuse/rejection rationale."), expandL4Tool(usage: "Use memory_os_expand_l4 before creating concept relations or when concept identity is ambiguous."), readRecordTool(), readProvenanceTool()]
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
        - Tool results are retrieval context, not final memory truth.
        - Do not invent evidence if a tool does not return enough context.
        - Do not output tool calls in the final artifact JSON.
        """
    }

    private static func searchTool(layers: [String], usage: String) -> MemoryOSBackgroundToolDescriptor {
        MemoryOSBackgroundToolDescriptor(
            name: "memory_os_search",
            description: "Search Connor Memory OS records across selected L0/L1/L2/L3/L4 layers and return ranked summaries, refs and expansion hints.",
            inputSchemaJSON: "{\"query\":\"string\",\"layers\":\(jsonArray(layers)),\"limit\":\"number\"}",
            usagePolicy: usage
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

    private static func jsonArray(_ values: [String]) -> String {
        let quoted = values.map { "\\\"\($0)\\\"" }.joined(separator: ",")
        return "[\(quoted)]"
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

    public func run(_ draft: MemoryOSL1ToL2JobDraft) throws -> MemoryOSBackgroundJobExecutionResult {
        let artifactType = "memory_os_l1_unified_projection"
        let tools = MemoryOSBackgroundToolCatalog.l1ToL2Tools()
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

    public func run(_ draft: MemoryOSL2ToKnowledgeJobDraft) throws -> MemoryOSBackgroundJobExecutionResult {
        let artifactType = "memory_os_knowledge_extraction"
        let tools = MemoryOSBackgroundToolCatalog.l2ToKnowledgeTools()
        let prompt = enrichedKnowledgePrompt(draft, tools: tools)
        let request = MemoryOSBackgroundModelRequest(
            jobID: draft.id,
            kind: draft.kind,
            schemaName: draft.schemaName,
            artifactType: artifactType,
            prompt: prompt,
            sourceRecordIDs: draft.statementIDs,
            evidenceSpanIDs: draft.evidenceSpanIDs,
            metadata: draft.metadata,
            availableTools: tools
        )
        let response = try executor.execute(request)
        return MemoryOSBackgroundJobExecutionResult(jobID: draft.id, kind: draft.kind, rawArtifactJSON: response.rawArtifactJSON, schemaName: draft.schemaName, artifactType: artifactType, metadata: draft.metadata.merging(response.metadata) { _, new in new })
    }

    private func enrichedL1Prompt(_ draft: MemoryOSL1ToL2JobDraft, tools: [MemoryOSBackgroundToolDescriptor]) -> String {
        """
        \(draft.prompt)

        \(MemoryOSBackgroundToolCatalog.promptSection(for: tools, stage: "L1→L2 extraction"))

        Stage-specific tool policy:
        - Prefer the provided L1 packet first.
        - Use memory_os_read_provenance when exact raw evidence is required.
        - Must use memory_os_search before deciding whether emitted L2 facts are new, duplicates, or refinements.
        - Must use memory_os_search across L3/L4 before emitting or rejecting L3 knowledge candidates, L4 stable entities, L4 concept entities, or L4 durable relations.
        - Record search-backed judgment in metadata or promotionDecisions: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        - Use memory_os_expand_l4 for entity identity ambiguity, duplicate concept detection, or relation context.

        Job contract:
        - job_id: \(draft.id)
        - capture_event_ids: \(draft.captureEventIDs.joined(separator: ","))
        - provenance_object_ids: \(draft.provenanceObjectIDs.joined(separator: ","))
        - source_span_ids: \(draft.sourceSpanIDs.joined(separator: ","))
        - output_schema: \(draft.schemaName)
        - semantic boundary: produce L2 operational facts, conservative L3 reusable knowledge candidates, and stable L4 entity/concept projections under evidence and promotion-policy constraints.
        """
    }

    private func enrichedKnowledgePrompt(_ draft: MemoryOSL2ToKnowledgeJobDraft, tools: [MemoryOSBackgroundToolDescriptor]) -> String {
        """
        \(draft.prompt)

        \(MemoryOSBackgroundToolCatalog.promptSection(for: tools, stage: "L2→Knowledge synthesis"))

        Stage-specific tool policy:
        - Must search L2, L3 and L4 before creating, reusing, or rejecting L3 knowledge, L4 concepts, concept relations, or refined L2 facts.
        - Record search-backed judgment for every accepted or rejected candidate: searched layers, duplicate/novelty outcome, reuse/rejection reason, and reused entity/concept ids when applicable.
        - Use memory_os_expand_l4 before adding concept relations or when concept identity is ambiguous.
        - Use memory_os_read_record only when summary-level context is insufficient.
        - Use memory_os_read_provenance when original evidence must be verified.

        Job contract:
        - job_id: \(draft.id)
        - statement_ids: \(draft.statementIDs.joined(separator: ","))
        - evidence_span_ids: \(draft.evidenceSpanIDs.joined(separator: ","))
        - output_schema: \(draft.schemaName)
        - retrieval: search L2/L3/L4 summaries first; request full records only when needed.
        - L4 expansion: use depth-limited concept/entity traversal when relation context is needed.
        - semantic boundary: use the four knowledge filters before proposing L3 knowledge.
        """
    }
}
