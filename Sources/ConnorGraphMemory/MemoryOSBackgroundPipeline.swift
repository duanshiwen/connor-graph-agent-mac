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

    public init(minPendingCount: Int = 100, maxEventsPerBlock: Int = 30, maxTokensPerBlock: Int = 12_000, maxPendingAge: TimeInterval? = 30 * 60) {
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

    public init(minPendingStatementCount: Int = 80, maxStatementsPerBlock: Int = 30, maxTokensPerBlock: Int = 12_000) {
        self.minPendingStatementCount = minPendingStatementCount
        self.maxStatementsPerBlock = maxStatementsPerBlock
        self.maxTokensPerBlock = maxTokensPerBlock
    }

    public func shouldTrigger(statements: [MemoryOSStatement]) -> Bool {
        pendingStatements(from: statements).count >= minPendingStatementCount
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

    public init(id: String = UUID().uuidString, kind: String = MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, captureEventIDs: [String], provenanceObjectIDs: [String], sourceSpanIDs: [String], schemaName: String = "GraphStructuredExtractionOutput", prompt: String, createdAt: Date = Date(), metadata: [String: String] = [:]) {
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
        You are processing Connor Memory OS L1 capture events into L2 operational facts.

        Layer semantics:
        - L0 is the durable provenance layer and source of raw evidence.
        - L1 is the active processing buffer / ordered memory sequence.
        - L2 is operational facts / working memory.
        - A successful L1→L2 projection clears the processed L1 buffer only after artifact acceptance; failures preserve L1 for retry or dead-letter review.

        Goal:
        - Extract only evidence-backed L2 operational facts / working memory.
        - Ignore noise, duplicates, transient wording and unsupported guesses.
        - You may search existing L2 operational memory before deciding whether a fact is new, duplicate or a refinement.
        - If raw L0 material is needed, request the referenced provenance object or span instead of guessing.
        - Output only GraphStructuredExtractionOutput JSON.

        Workflow:
        1. Read L1 events in chronological order.
        2. Extract candidate facts per event.
        3. Drop noise, transient wording, unsupported guesses and purely stylistic duplicates.
        4. Consolidate duplicate facts across events while preserving all evidence references.
        5. If a fact refines an existing L2 fact, emit append-only refinement material rather than overwriting history.
        6. Every emitted fact must cite at least one capture_event_id and at least one provenance_object_id or span_id.
        7. Do not create L3 knowledge records.
        8. Do not produce theories, frameworks, broad conclusions, or unsupported guesses.

        L1 capture events are provided as an ordered JSON packet:
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

        You may search L2, L3 and L4 before deciding whether to produce knowledge candidates, concept entities, concept relations or refined L2 facts.
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
        guard policy.shouldTrigger(statements: pending) else { return [] }
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
        [searchTool(layers: ["L2", "L4"], usage: "Use memory_os_search before emitting facts likely to duplicate existing L2 or when resolving L4 entity identity."), readProvenanceTool(), expandL4Tool(usage: "Use memory_os_expand_l4 only when L4 entity identity or relation context is necessary for grounded L2 extraction.")]
    }

    public static func l2ToKnowledgeTools() -> [MemoryOSBackgroundToolDescriptor] {
        [searchTool(layers: ["L2", "L3", "L4"], usage: "Search L3 and L4 before creating L3 knowledge or L4 concepts; search L2 when related operational context is needed."), expandL4Tool(usage: "Use memory_os_expand_l4 before creating concept relations or when concept identity is ambiguous."), readRecordTool(), readProvenanceTool()]
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
        let artifactType = "graph_structured_extraction"
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
        - Use memory_os_search before emitting facts likely to duplicate existing L2.
        - Use memory_os_expand_l4 only for entity identity ambiguity.

        Job contract:
        - job_id: \(draft.id)
        - capture_event_ids: \(draft.captureEventIDs.joined(separator: ","))
        - provenance_object_ids: \(draft.provenanceObjectIDs.joined(separator: ","))
        - source_span_ids: \(draft.sourceSpanIDs.joined(separator: ","))
        - output_schema: \(draft.schemaName)
        - semantic boundary: produce L2 operational facts only; do not create L3 knowledge records.
        """
    }

    private func enrichedKnowledgePrompt(_ draft: MemoryOSL2ToKnowledgeJobDraft, tools: [MemoryOSBackgroundToolDescriptor]) -> String {
        """
        \(draft.prompt)

        \(MemoryOSBackgroundToolCatalog.promptSection(for: tools, stage: "L2→Knowledge synthesis"))

        Stage-specific tool policy:
        - Search L3 and L4 before creating L3 knowledge or L4 concepts.
        - Use memory_os_expand_l4 before adding concept relations.
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
