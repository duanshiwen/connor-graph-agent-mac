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
        let eventSummary = events.map { event in
            "- capture_event_id=\(event.id), source=\(event.eventType), provenance_object_id=\(event.provenanceObjectID), span_id=\(event.metadata["span_id"] ?? "")"
        }.joined(separator: "\n")
        return """
        You are processing Connor Memory OS L1 capture events into L2 operational facts.

        Goal:
        - Extract only evidence-backed L2 operational facts / working memory.
        - Ignore noise, duplicates, transient wording and unsupported guesses.
        - You may search existing L2 operational memory before deciding whether a fact is new, duplicate or a refinement.
        - If raw L0 material is needed, request the referenced provenance object or span instead of guessing.
        - Output only GraphStructuredExtractionOutput JSON.

        L1 capture events:
        \(eventSummary)
        """
    }
}

public struct MemoryOSL2ToKnowledgePromptBuilder: Sendable {
    public init() {}

    public func prompt(for statements: [MemoryOSStatement]) -> String {
        let statementSummary = statements.map { statement in
            "- statement_id=\(statement.id), predicate=\(statement.predicate), text=\(statement.text), evidence=\(statement.evidenceSpanIDs.joined(separator: ","))"
        }.joined(separator: "\n")
        return """
        You are synthesizing Connor Memory OS L2 operational facts into reusable L3 knowledge and L4 concept graph records.

        Use the four knowledge filters:
        1. signal quality: is this knowledge rather than noise?
        2. reuse scope: will this be reusable in the future?
        3. novelty: is this new or a material enrichment?
        4. structurability: can it be mapped to category, knowledge type, scope, domain, work object/person and concept entities?

        You may search L2, L3 and L4 before deciding whether to produce knowledge candidates, concept entities, concept relations or refined L2 facts.
        Do not promote ordinary personal or operational facts into L3. If a fact should be more accurate, propose refined L2 facts as append-only follow-up material rather than overwriting history.
        Output only MemoryOSKnowledgeExtractionOutput JSON for accepted knowledge candidates and L4 concepts/relations.

        L2 statements:
        \(statementSummary)
        """
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

public struct MemoryOSBackgroundModelRequest: Sendable, Codable, Equatable {
    public var jobID: String
    public var kind: String
    public var schemaName: String
    public var artifactType: String
    public var prompt: String
    public var sourceRecordIDs: [String]
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]

    public init(jobID: String, kind: String, schemaName: String, artifactType: String, prompt: String, sourceRecordIDs: [String] = [], evidenceSpanIDs: [String] = [], metadata: [String: String] = [:]) {
        self.jobID = jobID
        self.kind = kind
        self.schemaName = schemaName
        self.artifactType = artifactType
        self.prompt = prompt
        self.sourceRecordIDs = sourceRecordIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.metadata = metadata
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
        let prompt = enrichedL1Prompt(draft)
        let request = MemoryOSBackgroundModelRequest(
            jobID: draft.id,
            kind: draft.kind,
            schemaName: draft.schemaName,
            artifactType: artifactType,
            prompt: prompt,
            sourceRecordIDs: draft.captureEventIDs,
            evidenceSpanIDs: draft.sourceSpanIDs,
            metadata: draft.metadata
        )
        let response = try executor.execute(request)
        return MemoryOSBackgroundJobExecutionResult(jobID: draft.id, kind: draft.kind, rawArtifactJSON: response.rawArtifactJSON, schemaName: draft.schemaName, artifactType: artifactType, metadata: draft.metadata.merging(response.metadata) { _, new in new })
    }

    public func run(_ draft: MemoryOSL2ToKnowledgeJobDraft) throws -> MemoryOSBackgroundJobExecutionResult {
        let artifactType = "memory_os_knowledge_extraction"
        let prompt = enrichedKnowledgePrompt(draft)
        let request = MemoryOSBackgroundModelRequest(
            jobID: draft.id,
            kind: draft.kind,
            schemaName: draft.schemaName,
            artifactType: artifactType,
            prompt: prompt,
            sourceRecordIDs: draft.statementIDs,
            evidenceSpanIDs: draft.evidenceSpanIDs,
            metadata: draft.metadata
        )
        let response = try executor.execute(request)
        return MemoryOSBackgroundJobExecutionResult(jobID: draft.id, kind: draft.kind, rawArtifactJSON: response.rawArtifactJSON, schemaName: draft.schemaName, artifactType: artifactType, metadata: draft.metadata.merging(response.metadata) { _, new in new })
    }

    private func enrichedL1Prompt(_ draft: MemoryOSL1ToL2JobDraft) -> String {
        """
        \(draft.prompt)

        Job contract:
        - job_id: \(draft.id)
        - capture_event_ids: \(draft.captureEventIDs.joined(separator: ","))
        - provenance_object_ids: \(draft.provenanceObjectIDs.joined(separator: ","))
        - source_span_ids: \(draft.sourceSpanIDs.joined(separator: ","))
        - output_schema: \(draft.schemaName)
        - semantic boundary: produce L2 operational facts only; do not create L3 knowledge records.
        """
    }

    private func enrichedKnowledgePrompt(_ draft: MemoryOSL2ToKnowledgeJobDraft) -> String {
        """
        \(draft.prompt)

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
