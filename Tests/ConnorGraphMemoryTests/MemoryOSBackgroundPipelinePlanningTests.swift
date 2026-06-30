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
    #expect(jobs.first?.prompt.contains("L2 entity-centered working memory") == true)
    #expect(jobs.first?.prompt.contains("memory_os_context") == true)
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


@Test func backgroundJobKindsExposeOnlyL1ExecutableKinds() throws {
    #expect(MemoryOSBackgroundJobKind.allCases == [.l1SynthesizeKnowledge, .l1UnifiedProjection])
    #expect(MemoryOSBackgroundJobKind.l1ExecutableRawValues == [
        MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
        MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue
    ])
}
