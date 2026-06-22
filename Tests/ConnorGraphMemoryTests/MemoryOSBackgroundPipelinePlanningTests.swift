import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l1ToL2PlannerCreatesFactExtractionJobsWhenThresholdIsMet() throws {
    let now = Date(timeIntervalSince1970: 2_000)
    let events = (0..<5).map { index in
        MemoryOSCaptureEvent(
            id: "capture-\(index)",
            provenanceObjectID: "object-\(index)",
            eventType: MemoryOSSourceType.chatMessage.rawValue,
            occurredAt: now.addingTimeInterval(Double(index)),
            tokenEstimate: 100,
            processingState: .pending,
            metadata: ["span_id": "span-\(index)"]
        )
    }
    let policy = MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 3, maxEventsPerBlock: 2, maxTokensPerBlock: 250)

    let jobs = MemoryOSL1ToL2JobPlanner(policy: policy).planJobs(from: events, now: now)

    #expect(jobs.count == 3)
    #expect(jobs.first?.kind == MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue)
    #expect(jobs.first?.captureEventIDs == ["capture-0", "capture-1"])
    #expect(jobs.first?.sourceSpanIDs == ["span-0", "span-1"])
    #expect(jobs.first?.schemaName == "GraphStructuredExtractionOutput")
    #expect(jobs.first?.prompt.contains("L2 operational facts") == true)
    #expect(jobs.first?.prompt.contains("search existing L2") == true)
}

@Test func l1ToL2PlannerDoesNotCreateJobsBelowThreshold() throws {
    let event = MemoryOSCaptureEvent(
        id: "capture-1",
        provenanceObjectID: "object-1",
        eventType: MemoryOSSourceType.chatMessage.rawValue,
        occurredAt: Date(timeIntervalSince1970: 2_000),
        tokenEstimate: 100,
        processingState: .pending,
        metadata: ["span_id": "span-1"]
    )
    let policy = MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 3, maxEventsPerBlock: 2, maxTokensPerBlock: 250)

    let jobs = MemoryOSL1ToL2JobPlanner(policy: policy).planJobs(from: [event], now: Date(timeIntervalSince1970: 2_100))

    #expect(jobs.isEmpty)
}

@Test func l2ToKnowledgePlannerCreatesKnowledgeSynthesisJobForUnorganizedStatements() throws {
    let now = Date(timeIntervalSince1970: 3_000)
    let statements = (0..<4).map { index in
        MemoryOSStatement(
            id: "statement-\(index)",
            subjectID: "node-\(index)",
            predicate: "observed",
            text: "事实 \(index)",
            assertionKind: .observed,
            confidence: 0.8,
            validAt: now,
            committedAt: now,
            evidenceSpanIDs: ["span-\(index)"],
            metadata: ["processing_state": "pending_knowledge_synthesis"]
        )
    }
    let policy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 3, maxStatementsPerBlock: 2)

    let jobs = MemoryOSL2ToKnowledgeJobPlanner(policy: policy).planJobs(from: statements, now: now)

    #expect(jobs.count == 2)
    #expect(jobs.first?.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
    #expect(jobs.first?.statementIDs == ["statement-0", "statement-1"])
    #expect(jobs.first?.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(jobs.first?.prompt.contains("four knowledge filters") == true)
    #expect(jobs.first?.prompt.contains("search L2, L3 and L4") == true)
    #expect(jobs.first?.prompt.contains("refined L2 facts") == true)
}
