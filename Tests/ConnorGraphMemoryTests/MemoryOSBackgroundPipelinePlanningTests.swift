import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l1UnifiedProjectionPlannerCreatesFactExtractionJobsWhenThresholdIsMet() throws {
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

    let jobs = MemoryOSL1UnifiedProjectionJobPlanner(policy: policy).planJobs(from: events, now: now)

    #expect(jobs.count == 3)
    #expect(jobs.first?.kind == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
    #expect(jobs.first?.captureEventIDs == ["capture-0", "capture-1"])
    #expect(jobs.first?.sourceSpanIDs == ["span-0", "span-1"])
    #expect(jobs.first?.schemaName == "MemoryOSL1UnifiedProjectionOutput")
    #expect(jobs.first?.prompt.contains("L2 operational facts") == true)
    #expect(jobs.first?.prompt.contains("search existing L2") == true)
}

@Test func l1UnifiedProjectionPlannerDoesNotCreateJobsBelowThreshold() throws {
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

    let jobs = MemoryOSL1UnifiedProjectionJobPlanner(policy: policy).planJobs(from: [event], now: Date(timeIntervalSince1970: 2_100))

    #expect(jobs.isEmpty)
}

@Test func l1UnifiedProjectionPlannerDoesNotTriggerBeforeDefault24HourAgeThreshold() throws {
    let occurredAt = Date(timeIntervalSince1970: 2_000)
    let event = MemoryOSCaptureEvent(
        id: "capture-1",
        provenanceObjectID: "object-1",
        eventType: MemoryOSSourceType.chatMessage.rawValue,
        occurredAt: occurredAt,
        tokenEstimate: 100,
        processingState: .pending,
        metadata: ["span_id": "span-1"]
    )

    let jobs = MemoryOSL1UnifiedProjectionJobPlanner().planJobs(from: [event], now: occurredAt.addingTimeInterval((24 * 60 * 60) - 1))

    #expect(jobs.isEmpty)
}

@Test func l1UnifiedProjectionPlannerTriggersAtDefault24HourAgeThreshold() throws {
    let occurredAt = Date(timeIntervalSince1970: 2_000)
    let event = MemoryOSCaptureEvent(
        id: "capture-1",
        provenanceObjectID: "object-1",
        eventType: MemoryOSSourceType.chatMessage.rawValue,
        occurredAt: occurredAt,
        tokenEstimate: 100,
        processingState: .pending,
        metadata: ["span_id": "span-1"]
    )

    let jobs = MemoryOSL1UnifiedProjectionJobPlanner().planJobs(from: [event], now: occurredAt.addingTimeInterval(24 * 60 * 60))

    #expect(jobs.count == 1)
    #expect(jobs.first?.captureEventIDs == ["capture-1"])
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

@Test func l2ToKnowledgePlannerDoesNotTriggerBeforeDefault24HourAgeThreshold() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let statement = MemoryOSStatement(
        id: "statement-1",
        subjectID: "node-1",
        predicate: "observed",
        text: "事实 1",
        assertionKind: .observed,
        confidence: 0.8,
        validAt: now.addingTimeInterval(-(24 * 60 * 60) + 1),
        committedAt: now.addingTimeInterval(-(24 * 60 * 60) + 1),
        evidenceSpanIDs: ["span-1"],
        metadata: ["processing_state": "pending_knowledge_synthesis"]
    )

    let jobs = MemoryOSL2ToKnowledgeJobPlanner().planJobs(from: [statement], now: now)

    #expect(jobs.isEmpty)
}

@Test func l2ToKnowledgePlannerTriggersAtDefault24HourAgeThreshold() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let statement = MemoryOSStatement(
        id: "statement-1",
        subjectID: "node-1",
        predicate: "observed",
        text: "事实 1",
        assertionKind: .observed,
        confidence: 0.8,
        validAt: now.addingTimeInterval(-24 * 60 * 60),
        committedAt: now.addingTimeInterval(-24 * 60 * 60),
        evidenceSpanIDs: ["span-1"],
        metadata: ["processing_state": "pending_knowledge_synthesis"]
    )

    let jobs = MemoryOSL2ToKnowledgeJobPlanner().planJobs(from: [statement], now: now)

    #expect(jobs.count == 1)
    #expect(jobs.first?.statementIDs == ["statement-1"])
}

@Test func l1PolicyReportsCountThresholdReasonAtDefault100PendingEvents() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let events = (0..<100).map { index in
        MemoryOSCaptureEvent(
            id: "capture-default-\(index)",
            provenanceObjectID: "object-default-\(index)",
            eventType: MemoryOSSourceType.chatMessage.rawValue,
            occurredAt: now.addingTimeInterval(Double(index)),
            tokenEstimate: 10,
            processingState: .pending,
            metadata: [:]
        )
    }

    let reason = MemoryOSL1ProcessingTriggerPolicy().triggerReason(events: events, now: now)

    #expect(reason == .pendingCountThreshold)
}

@Test func l2PolicyDefaultRequires100PendingStatements() throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let statements = (0..<99).map { index in
        MemoryOSStatement(
            id: "statement-default-\(index)",
            subjectID: "node-\(index)",
            predicate: "observed",
            text: "事实 \(index)",
            assertionKind: .observed,
            confidence: 0.8,
            validAt: now,
            committedAt: now,
            evidenceSpanIDs: [],
            metadata: ["processing_state": "pending_knowledge_synthesis"]
        )
    }

    let policy = MemoryOSL2KnowledgeSynthesisTriggerPolicy()

    #expect(policy.minPendingStatementCount == 100)
    #expect(policy.triggerReason(statements: statements, now: now) == nil)
    #expect(policy.triggerReason(statements: statements + [MemoryOSStatement(id: "statement-default-99", subjectID: "node-99", predicate: "observed", text: "事实 99", assertionKind: .observed, confidence: 0.8, validAt: now, committedAt: now, evidenceSpanIDs: [], metadata: ["processing_state": "pending_knowledge_synthesis"])], now: now) == .pendingCountThreshold)
}
