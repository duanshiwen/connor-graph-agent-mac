import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphSearch
import ConnorGraphAppSupport

@Suite("Memory OS CLI Inspector Tests")
struct AppMemoryOSCLIInspectorTests {
    @Test func memoryOSCLIInspectorReportsEmptyStoreStatus() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let status = try inspector.status(now: Date(timeIntervalSince1970: 1_000))

        #expect(status.databasePath.hasSuffix(".sqlite"))
        #expect(status.schema.expectedVersion == SQLiteMemoryOSStore.currentSchemaVersion)
        #expect(status.schema.health == "healthy")
        #expect(status.layers.l0ProvenanceObjects == 0)
        #expect(status.layers.l1CaptureEvents == 0)
        #expect(status.layers.l2Statements == 0)
        #expect(status.layers.l3Beliefs == 0)
        #expect(status.layers.l4Entities == 0)
        #expect(status.queue.pending == 0)
    }

    @Test func memoryOSCLIInspectorReportsLayerCounts() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let stats = try inspector.stats()
        let layers = try inspector.layers()

        #expect(stats.tables["memory_l0_provenance_objects"] == 1)
        #expect(stats.tables["memory_l0_provenance_spans"] == 1)
        #expect(stats.tables["memory_l1_capture_events"] == 1)
        #expect(stats.tables["memory_l2_statements"] == 1)
        #expect(stats.tables["memory_l2_statement_processing_state"] == 1)
        #expect(stats.tables["memory_l3_beliefs"] == 1)
        #expect(stats.tables["memory_l4_entities"] == 1)
        #expect(layers.l0.objects == 1)
        #expect(layers.l0.spans == 1)
        #expect(layers.l1.captureEvents == 1)
        #expect(layers.l1.pending == 1)
        #expect(layers.l2.statements == 1)
        #expect(layers.l2.knowledgePending == 1)
        #expect(layers.l3.beliefs == 1)
        #expect(layers.l4.entities == 1)
    }

    @Test func memoryOSCLIInspectorListsL0ObjectsAndSpans() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let objects = try inspector.listL0Objects(limit: 10)
        let spans = try inspector.listL0Spans(limit: 10)

        #expect(objects.count == 1)
        #expect(objects[0].values["id"] == "object-1")
        #expect(objects[0].values["source_type"] == "chat_message")
        #expect(objects[0].values["title"] == "User message")
        #expect(objects[0].values["content"] == "诗闻正在测试 Connor Memory OS CLI。")
        #expect(spans.count == 1)
        #expect(spans[0].values["id"] == "span-1")
        #expect(spans[0].values["provenance_object_id"] == "object-1")
        #expect(spans[0].values["text"] == "Connor Memory OS CLI")
    }

    @Test func memoryOSCLIInspectorListsL1PendingCaptureEvents() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let events = try inspector.listL1Pending(limit: 10)

        #expect(events.count == 1)
        #expect(events[0].values["id"] == "event-1")
        #expect(events[0].values["processing_state"] == "pending")
        #expect(events[0].values["token_estimate"] == "12")
        #expect(events[0].values["provenance_title"] == "User message")
        #expect(events[0].values["provenance_content"] == "诗闻正在测试 Connor Memory OS CLI。")
        #expect(events[0].values["content"] == "诗闻正在测试 Connor Memory OS CLI。")
    }

    @Test func memoryOSCLIInspectorListsL2StatementsAndPendingKnowledge() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let statements = try inspector.listL2Statements(limit: 10)
        let pending = try inspector.listL2PendingKnowledge(limit: 10)

        #expect(statements.count == 1)
        #expect(statements[0].values["id"] == "stmt-1")
        #expect(statements[0].values["predicate"] == "describes")
        #expect(statements[0].values["source_artifact_id"] == "artifact-1")
        #expect(pending.count == 1)
        #expect(pending[0].values["statement_id"] == "stmt-1")
        #expect(pending[0].values["processing_kind"] == "knowledge_synthesis")
        #expect(pending[0].values["status"] == "pending")
        #expect(pending[0].values["statement_text"] == "Connor Memory OS 是康纳同学的重要系统。")
        #expect(pending[0].values["evidence_span_texts"] == "Connor Memory OS CLI")
    }

    @Test func memoryOSCLIInspectorListsL3Beliefs() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let beliefs = try inspector.listL3Beliefs(limit: 10)

        #expect(beliefs.count == 1)
        #expect(beliefs[0].values["id"] == "belief-1")
        #expect(beliefs[0].values["topic"] == "Connor Memory OS")
        #expect(beliefs[0].values["source_artifact_id"] == "artifact-2")
    }

    @Test func memoryOSCLIInspectorListsL4Entities() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let entities = try inspector.listL4Entities(limit: 10)

        #expect(entities.count == 1)
        #expect(entities[0].values["id"] == "entity-1")
        #expect(entities[0].values["entity_type"] == "concept")
        #expect(entities[0].values["name"] == "Connor Memory OS")
    }

    @Test func memoryOSCLIInspectorReadsRecordByLayerAndID() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let l0 = try #require(try inspector.read(layer: "L0", id: "object-1"))
        let l1 = try #require(try inspector.read(layer: "L1", id: "event-1"))
        let l2 = try #require(try inspector.read(layer: "L2", id: "stmt-1"))
        let l3 = try #require(try inspector.read(layer: "L3", id: "belief-1"))
        let l4 = try #require(try inspector.read(layer: "L4", id: "entity-1"))

        #expect(l0.layer == "L0")
        #expect(l0.record.values["id"] == "object-1")
        #expect(l1.layer == "L1")
        #expect(l1.record.values["id"] == "event-1")
        #expect(l1.record.values["provenance_title"] == "User message")
        #expect(l1.record.values["provenance_content"] == "诗闻正在测试 Connor Memory OS CLI。")
        #expect(l1.record.values["content"] == "诗闻正在测试 Connor Memory OS CLI。")
        #expect(l2.layer == "L2")
        #expect(l2.record.values["id"] == "stmt-1")
        #expect(l3.layer == "L3")
        #expect(l3.record.values["id"] == "belief-1")
        #expect(l4.layer == "L4")
        #expect(l4.record.values["id"] == "entity-1")
    }

    @Test func memoryOSCLIInspectorReturnsNilForMissingRecord() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let missing = try inspector.read(layer: "L2", id: "missing-statement")

        #expect(missing == nil)
    }

    @Test func memoryOSCLIInspectorAcceptsLayerAliases() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        #expect(try inspector.read(layer: "provenance", id: "object-1")?.layer == "L0")
        #expect(try inspector.read(layer: "capture", id: "event-1")?.layer == "L1")
        #expect(try inspector.read(layer: "statement", id: "stmt-1")?.layer == "L2")
        #expect(try inspector.read(layer: "belief", id: "belief-1")?.layer == "L3")
        #expect(try inspector.read(layer: "entity", id: "entity-1")?.layer == "L4")
    }

    @Test func memoryOSCLIInspectorSearchesL2Statements() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Connor", layers: ["L2"], limit: 10)

        #expect(result.query == "Connor")
        #expect(result.hits.count == 1)
        #expect(result.hits[0].layer == "L2")
        #expect(result.hits[0].id == "stmt-1")
    }

    @Test func memoryOSCLIInspectorSearchesAcrossL3AndL4() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Memory", layers: ["L3", "L4"], limit: 10)

        #expect(result.hits.map(\.layer).contains("L3"))
        #expect(result.hits.map(\.layer).contains("L4"))
    }

    @Test func memoryOSCLIInspectorSearchRespectsLayerFilterAndLimit() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Memory", layers: ["L4"], limit: 1)

        #expect(result.hits.count == 1)
        #expect(result.hits.allSatisfy { $0.layer == "L4" })
    }

    @Test func memoryOSCLIRouterRoutesBackgroundRunsCommands() throws {
    let store = try makeMemoryOSCLIInspectorStore()
    let now = Date(timeIntervalSince1970: 10_000)
    try store.save(backgroundRun: MemoryOSBackgroundRunRecord(id: "run-1", queueItemID: "queue-1", kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, source: "l1_capture_events", status: .succeeded, startedAt: now, finishedAt: now, modelID: "model", statelessBatch: true))
    try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(id: "msg-1", runID: "run-1", sequence: 0, role: .user, content: "batch prompt"))
    try store.save(backgroundToolCall: MemoryOSBackgroundToolCallRecord(id: "tool-1", runID: "run-1", iteration: 1, toolName: "memory_os_search", argumentsJSON: "{}", status: .succeeded, startedAt: now, finishedAt: now))
    let inspector = AppMemoryOSCLIInspector(store: store, databasePath: store.databasePath)
    let encoder = JSONEncoder()

    let runs = try AppMemoryOSCLIRouter.route(args: ["runs"], inspector: inspector, encoder: encoder)
    let messages = try AppMemoryOSCLIRouter.route(args: ["run", "run-1", "messages"], inspector: inspector, encoder: encoder)
    let toolCalls = try AppMemoryOSCLIRouter.route(args: ["run", "run-1", "tool-calls"], inspector: inspector, encoder: encoder)

    #expect(runs.contains("run-1"))
    #expect(runs.contains("statelessBatch"))
    #expect(messages.contains("batch prompt"))
    #expect(toolCalls.contains("memory_os_search"))
}

@Test func memoryOSCLIInspectorListsQueueItems() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let now = Date(timeIntervalSince1970: 20_000)
        try seedMemoryOSCLIInspectorFixture(store: store, now: now)
        let inspector = AppMemoryOSCLIInspector(store: store)
        _ = try inspector.planL1(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)

        let queue = try inspector.queue(limit: 10, status: "pending", kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)

        #expect(queue.count == 1)
        #expect(queue[0].values["kind"] == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
        #expect(queue[0].values["status"] == "pending")
        #expect(queue[0].values["context_text"] == "诗闻正在测试 Connor Memory OS CLI。")
    }

    @Test func memoryOSCLIInspectorReportsPipelinePolicy() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let policy = inspector.pipelinePolicy()

        #expect(policy.l1UnifiedProjection.maxPendingAgeSeconds == 86_400)
        #expect(policy.l2ToKnowledge.maxPendingAgeSeconds == 86_400)
        #expect(policy.l1UnifiedProjection.minPendingCount == 100)
        #expect(policy.l2ToKnowledge.minPendingStatementCount == 100)
    }

    @Test func memoryOSCLIInspectorPlansL1AndL2JobsThroughFacade() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let now = Date(timeIntervalSince1970: 30_000)
        try seedMemoryOSCLIInspectorFixture(store: store, now: now)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let l1Plan = try inspector.planL1(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)
        let l2Plan = try inspector.planL2(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 1, maxStatementsPerBlock: 10), now: now)

        #expect(l1Plan.plannedJobs == 1)
        #expect(l1Plan.kind == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
        #expect(l1Plan.jobIDs.count == 1)
        #expect(l2Plan.plannedJobs == 1)
        #expect(l2Plan.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
        #expect(l2Plan.jobIDs.count == 1)
    }

    @Test func memoryOSCLIRouterRoutesPipelineDebugRunNextCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)
        let output = try AppMemoryOSCLIRouter.route(
            args: ["pipeline", "debug-run-next", "--kind", MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, "--limit", "1", "--format", "json"],
            inspector: inspector,
            encoder: memoryOSCLITestEncoder()
        )

        #expect(output.contains("debug-run-next"))
        #expect(output.contains("no_runnable_jobs"))
        #expect(output.contains("requested_kind"))
        #expect(output.contains(MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue))
        #expect(output.contains("queue_runs"))
    }

    @Test func memoryOSCLIRouterRoutesPipelineDebugRunNextTextFormat() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)
        let output = try AppMemoryOSCLIRouter.route(
            args: ["pipeline", "debug-run-next", "--format", "text"],
            inspector: inspector,
            encoder: memoryOSCLITestEncoder()
        )

        #expect(output.contains("Memory OS Debug AI Run"))
        #expect(output.contains("No runnable background AI jobs"))
        #expect(output.contains("plan-l1"))
    }

    @Test func memoryOSCLIDebugTranscriptRendererIncludesMessagesAndToolCalls() throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let result = MemoryOSCLIDebugAIRunResult(
            status: "completed",
            command: "memory pipeline debug-run-next",
            requestedKind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            requestedLimit: 1,
            queueRuns: [MemoryOSCLIDebugAIQueueRun(
                queueItemID: "queue-1",
                kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
                runID: "memory-run:queue-1",
                modelID: "model",
                status: "succeeded",
                messageCount: 2,
                toolCallCount: 1,
                projectionSummary: MemoryOSProjectionRunSummary(artifactID: "artifact-1", accepted: true, statementCount: 1),
                messages: [
                    MemoryOSBackgroundMessageRecord(id: "msg-1", runID: "memory-run:queue-1", sequence: 0, role: .user, content: "Prompt sent to AI"),
                    MemoryOSBackgroundMessageRecord(id: "msg-2", runID: "memory-run:queue-1", sequence: 1, role: .assistant, content: "Assistant response")
                ],
                toolCalls: [MemoryOSBackgroundToolCallRecord(id: "tool-1", runID: "memory-run:queue-1", iteration: 1, toolName: "memory_os_search", argumentsJSON: "{}", resultJSON: "{\"hits\":[]}", status: .succeeded, startedAt: now, finishedAt: now)]
            )]
        )

        let transcript = MemoryOSDebugAIRunTranscriptRenderer.render(result)

        #expect(transcript.contains("Prompt sent to AI"))
        #expect(transcript.contains("Assistant response"))
        #expect(transcript.contains("memory_os_search"))
        #expect(transcript.contains("Projection: accepted=true"))
        #expect(transcript.contains("swift run connor memory run memory-run:queue-1 messages"))
    }

    @Test func memoryOSCLIDebugRunNextExecutesQueueWithTrace() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let now = Date(timeIntervalSince1970: 40_000)
        try seedMemoryOSCLIInspectorFixture(store: store, now: now)
        let inspector = AppMemoryOSCLIInspector(store: store)
        let plan = try inspector.planL1(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)
        let queueID = try #require(plan.jobIDs.first)
        let model = MemoryOSCLIDebugScriptedLoopModel(script: [
            MemoryOSBackgroundLoopModelResponse(
                assistantText: "Searching before projection.",
                toolCalls: [MemoryOSBackgroundToolCall(id: "tool-1", name: "memory_os_search", argumentsJSON: #"{"query":"Connor","layers":["L2","L3","L4"],"limit":5}"#)]
            ),
            MemoryOSBackgroundLoopModelResponse(finalArtifactJSON: try memoryOSCLIDebugEncodedL1Artifact(), metadata: ["final": "true"])
        ])

        let result = try inspector.debugRunNextBackgroundAI(
            kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            limit: 1,
            model: model,
            configuration: MemoryOSBackgroundToolLoopConfiguration(maxToolIterations: 4),
            now: now
        )

        let run = try #require(result.queueRuns.first)
        #expect(result.status == "completed")
        #expect(run.queueItemID == queueID)
        #expect(run.runID == "memory-run:\(queueID)")
        #expect(run.modelID == "cli-debug-scripted-model")
        #expect(run.status == "succeeded")
        #expect(run.messageCount >= 3)
        #expect(run.toolCallCount == 1)
        #expect(run.messages.contains { $0.role == .assistant && $0.content == "Searching before projection." })
        #expect(run.toolCalls.first?.toolName == "memory_os_search")
        #expect(run.projectionSummary?.accepted == true)
    }

    @Test func memoryOSCLIRouterRoutesStatusCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let output = try AppMemoryOSCLIRouter.route(args: ["status"], inspector: AppMemoryOSCLIInspector(store: store), encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"schema\""))
        #expect(output.contains("\"layers\""))
    }

    @Test func memoryOSCLIRouterRoutesLayerListCommands() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["l2", "statements", "--limit", "5"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("stmt-1"))
        #expect(output.contains("describes"))
    }

    @Test func memoryOSCLIRouterRoutesReadCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["read", "L4", "entity-1"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"layer\" : \"L4\""))
        #expect(output.contains("entity-1"))
    }

    @Test func memoryOSCLIRouterRoutesQueryGraphCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let output = try AppMemoryOSCLIRouter.route(args: ["query-graph", "Connor", "--intent", "auto", "--include-evidence", "--limit", "10"], inspector: inspector, encoder: encoder)

        #expect(output.contains("entity-1"))
        #expect(output.contains("stmt-1"))
        #expect(output.contains("belief-1"))
        #expect(output.contains("span-1"))
        #expect(output.contains("object-1"))
        #expect(output.contains("query_graph"))
    }

    @Test func memoryOSQueryGraphGoldenIntents() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let now = Date(timeIntervalSince1970: 10_000)
        try store.upsert(entity: MemoryOSEntity(id: "class-memory-system", stableKey: "class:memory-system", entityType: "class", name: "Memory System", aliases: ["记忆系统"], summary: "Memory system class", confidence: 0.9, createdAt: now, updatedAt: now))
        try store.upsert(entityStatement: MemoryOSEntityStatement(id: "entity-is-instance", entityID: "entity-1", predicate: .instanceOf, objectEntityID: "class-memory-system", text: "Connor Memory OS is an instance of Memory System.", confidence: 0.9, validAt: now, committedAt: now))
        let inspector = AppMemoryOSCLIInspector(store: store)

        let l2 = try inspector.queryGraph(text: "Connor", intent: .l2Statements, entityID: nil, classEntityIDs: [], predicates: ["describes"], direction: .both, includeEvidence: true, limit: 10)
        #expect(l2.nodes.contains { $0.id == "stmt-1" && $0.layer == .l2 })
        #expect(l2.edges.contains { $0.predicate == "evidenced_by" })
        #expect(l2.nodes.contains { $0.id == "span-1" && $0.layer == .l0 })

        let l3 = try inspector.queryGraph(text: "observable", intent: .l3Beliefs, entityID: nil, classEntityIDs: [], predicates: [], direction: .both, includeEvidence: true, limit: 10)
        #expect(l3.nodes.contains { $0.id == "belief-1" && $0.layer == .l3 })
        #expect(l3.edges.contains { $0.predicate == "supported_by" })

        let l4Entity = try inspector.queryGraph(text: "Memory OS", intent: .l4Entity, entityID: nil, classEntityIDs: [], predicates: [], direction: .both, includeEvidence: false, limit: 10)
        #expect(l4Entity.nodes.contains { $0.id == "entity-1" && $0.layer == .l4 })

        let l4Instances = try inspector.queryGraph(text: "记忆系统", intent: .l4Instances, entityID: nil, classEntityIDs: ["class-memory-system"], predicates: ["INSTANCE_OF"], direction: .both, includeEvidence: false, limit: 10)
        #expect(l4Instances.nodes.contains { $0.id == "entity-1" && $0.layer == .l4 })
        #expect(l4Instances.edges.contains { $0.id == "entity-is-instance" && $0.predicate == "INSTANCE_OF" })
    }

    @Test func memoryOSCLIRouterRoutesTraceEvidenceCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let output = try AppMemoryOSCLIRouter.route(args: ["trace", "evidence", "--statement", "stmt-1", "--limit", "10"], inspector: inspector, encoder: encoder)

        #expect(output.contains("stmt-1"))
        #expect(output.contains("span-1"))
        #expect(output.contains("object-1"))
        #expect(output.contains("evidenced_by"))
    }

    @Test func memoryOSCLIRouterRoutesL2FindCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let output = try AppMemoryOSCLIRouter.route(args: ["l2", "find", "康纳", "--predicate", "describes", "--limit", "5"], inspector: inspector, encoder: encoder)

        #expect(output.contains("stmt-1"))
        #expect(output.contains("node-1"))
        #expect(output.contains("span-1"))
    }

    @Test func memoryOSCLIRouterRoutesL3ExpandCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let output = try AppMemoryOSCLIRouter.route(args: ["l3", "expand", "observable", "--limit", "5"], inspector: inspector, encoder: encoder)

        #expect(output.contains("belief-1"))
        #expect(output.contains("stmt-1"))
        #expect(output.contains("supported_by"))
    }

    @Test func memoryOSCLIInspectorListsL4Predicates() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let predicates = inspector.listL4Predicates()

        #expect(predicates.contains { $0.predicate == "INSTANCE_OF" && $0.category == "taxonomy" })
        #expect(predicates.contains { $0.predicate == "HAS_PART" && $0.inverse == "PART_OF" })
        #expect(predicates.contains { $0.predicate == "RELATED_TO" && $0.strict == false })
    }

    @Test func memoryOSCLIRouterRoutesL4PredicatesCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let output = try AppMemoryOSCLIRouter.route(args: ["l4", "predicates"], inspector: inspector, encoder: encoder)

        #expect(output.contains("INSTANCE_OF"))
        #expect(output.contains("retrieval_weight"))
        #expect(output.contains("taxonomy"))
    }

    @Test func memoryOSCLIRouterRoutesL4FindAndNeighborsCommands() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let now = Date(timeIntervalSince1970: 10_000)
        try store.upsert(entity: MemoryOSEntity(id: "entity-graph", stableKey: "concept:graph", entityType: "concept", name: "Graph", summary: "Graph concept", confidence: 0.9, createdAt: now, updatedAt: now))
        try store.upsert(entityStatement: MemoryOSEntityStatement(id: "entity-edge-1", entityID: "entity-1", predicate: .relatedTo, objectEntityID: "entity-graph", text: "Connor Memory OS relates to Graph.", confidence: 0.9, validAt: now, committedAt: now))
        let inspector = AppMemoryOSCLIInspector(store: store)
        let encoder = memoryOSCLITestEncoder()

        let find = try AppMemoryOSCLIRouter.route(args: ["l4", "find", "Memory OS"], inspector: inspector, encoder: encoder)
        #expect(find.contains("entity-1"))

        let neighbors = try AppMemoryOSCLIRouter.route(args: ["l4", "neighbors", "entity-1", "--direction", "outgoing"], inspector: inspector, encoder: encoder)
        #expect(neighbors.contains("entity-edge-1"))
        #expect(neighbors.contains("entity-graph"))
    }

    @Test func memoryOSCLIRouterRoutesSearchCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["search", "Memory", "--layers", "L3,L4", "--limit", "5"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"query\" : \"Memory\""))
        #expect(output.contains("\"layer\" : \"L3\"") || output.contains("\"layer\" : \"L4\""))
    }

    @Test func memoryOSCLIRouterRoutesSearchIndexCommands() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-cli-search-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let libraryURL = MemoryOSSearchKernel.defaultReleaseLibraryURL(repositoryRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        let kernel = try MemoryOSSearchKernel(libraryURL: libraryURL, indexDirectory: temp.appendingPathComponent("index", isDirectory: true))
        let inspector = AppMemoryOSCLIInspector(store: store, databasePath: store.databasePath, searchKernel: kernel)
        let encoder = memoryOSCLITestEncoder()

        let rebuild = try AppMemoryOSCLIRouter.route(args: ["search-index", "rebuild"], inspector: inspector, encoder: encoder)
        #expect(rebuild.contains("\"status\" : \"rebuilt\""))
        #expect(rebuild.contains("\"document_count\""))

        let stats = try AppMemoryOSCLIRouter.route(args: ["search-index", "stats"], inspector: inspector, encoder: encoder)
        #expect(stats.contains("\"connor_meta\""))
        #expect(stats.contains("\"index_size_bytes\""))
        #expect(stats.contains("sourceDatabaseFingerprint"))

        let verify = try AppMemoryOSCLIRouter.route(args: ["search-index", "verify"], inspector: inspector, encoder: encoder)
        #expect(verify.contains("\"status\" : \"ok\""))
        #expect(verify.contains("smoke_Memory"))
    }

    @Test func memoryOSCLIRouterReturnsHelpfulErrors() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["read", "L2"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("missing_layer_or_id"))
    }
}

private func makeMemoryOSCLIInspectorStore() throws -> SQLiteMemoryOSStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-cli-inspector-\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: url.path)
    try store.migrate()
    return store
}

private func memoryOSCLITestEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func seedMemoryOSCLIInspectorFixture(store: SQLiteMemoryOSStore, now: Date = Date(timeIntervalSince1970: 10_000)) throws {
    let object = MemoryOSProvenanceObject(
        id: "object-1",
        sourceType: .chatMessage,
        sourceID: "message-1",
        title: "User message",
        content: "诗闻正在测试 Connor Memory OS CLI。",
        contentHash: "hash-1",
        occurredAt: now,
        ingestedAt: now,
        sessionID: "session-1",
        metadata: ["fixture": "true"]
    )
    try store.upsert(provenance: object)
    let span = MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: object.id, startOffset: 0, endOffset: 18, text: "Connor Memory OS CLI", metadata: ["kind": "title"])
    try store.upsert(span: span)
    let event = MemoryOSCaptureEvent(id: "event-1", provenanceObjectID: object.id, eventType: "chat_message", occurredAt: now, tokenEstimate: 12, processingState: .pending, metadata: ["source": "test"])
    try store.upsert(captureEvent: event)

    let node = MemoryOSNode(id: "node-1", stableKey: "node:connor", nodeType: "project", name: "Connor Memory OS", summary: "Memory system", createdAt: now, updatedAt: now)
    try store.upsert(node: node)
    let statement = MemoryOSStatement(id: "stmt-1", subjectID: node.id, predicate: "describes", text: "Connor Memory OS 是康纳同学的重要系统。", confidence: 0.91, validAt: now, committedAt: now, evidenceSpanIDs: [span.id], sourceArtifactID: "artifact-1", metadata: ["stage": "l2"])
    try store.upsert(statement: statement)
    try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: statement.id, processingKind: .knowledgeSynthesis, status: .pending, sourceArtifactID: "artifact-1", lastAttemptAt: nil, metadata: ["reason": "new_statement"]))

    let belief = MemoryOSBelief(id: "belief-1", topic: "Connor Memory OS", statement: "Memory OS should be observable from CLI.", projectionKind: .summarized, confidence: 0.84, evidenceStatementIDs: [statement.id], validAt: now, projectedAt: now, sourceArtifactID: "artifact-2", metadata: ["stage": "l3"])
    try store.upsert(belief: belief)
    let entity = MemoryOSEntity(id: "entity-1", stableKey: "concept:connor-memory-os", entityType: "concept", name: "Connor Memory OS", aliases: ["Memory OS"], summary: "康纳同学的长期记忆系统", confidence: 0.93, createdAt: now, updatedAt: now, validFrom: now, metadata: ["stage": "l4"])
    try store.upsert(entity: entity)
}

private final class MemoryOSCLIDebugScriptedLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    let modelID = "cli-debug-scripted-model"
    private var script: [MemoryOSBackgroundLoopModelResponse]

    init(script: [MemoryOSBackgroundLoopModelResponse]) {
        self.script = script
    }

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse {
        guard !script.isEmpty else { return MemoryOSBackgroundLoopModelResponse(finalArtifactJSON: "{}") }
        return script.removeFirst()
    }
}

private func memoryOSCLIDebugEncodedL1Artifact() throws -> String {
    let output = MemoryOSL1UnifiedProjectionOutput(
        operationalEntities: [
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.93, evidenceSpanIDs: ["span-1"])
        ],
        operationalStatements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-debug-1", subjectLocalID: "project-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "Connor Memory OS 正在被 CLI 调试。", confidence: 0.91, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "Connor Memory OS CLI")],
        knowledgeCandidates: [],
        conceptEntities: [],
        conceptRelations: [],
        promotionDecisions: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}
