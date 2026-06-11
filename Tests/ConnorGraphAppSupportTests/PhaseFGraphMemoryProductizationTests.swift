import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Phase F Graph Memory Productization Tests")
struct PhaseFGraphMemoryProductizationTests {
    @Test func graphMemoryReviewCenterBuildsDashboardFromCandidatesHoldsAndChangeLog() throws {
        let store = try phaseFStore()
        let now = Date(timeIntervalSince1970: 1_000)
        try store.upsertWriteCandidate(GraphWriteCandidate(
            id: "candidate-low-confidence",
            groupID: "default",
            kind: .createFact,
            proposedByRunID: "run-1",
            rationale: "User preference extracted from conversation.",
            confidence: 0.42,
            payloadJSON: "{\"fact\":\"prefers graph memory\"}",
            sourceEpisodeIDs: ["episode-1"],
            status: .pendingReview,
            createdAt: now
        ))
        try store.upsertAdmissionHoldQueueItem(GraphAdmissionHoldQueueItem(
            id: "hold-missing-evidence",
            traceID: "trace-1",
            jobID: "job-1",
            graphID: "default",
            sourceID: "session-1",
            sourceType: .chat,
            reasons: [.missingStatementEvidence],
            recommendedActions: [.inspectEvidence, .groundSource],
            message: "Need evidence before memory commit.",
            createdAt: now.addingTimeInterval(10)
        ))
        try store.appendMemoryChangeLogEntry(GraphMemoryChangeLogEntry(
            id: "change-1",
            graphID: "default",
            action: .extractionCommitted,
            traceID: "trace-committed",
            jobID: "job-committed",
            sourceID: "session-2",
            sourceType: .chat,
            entityIDs: ["entity-1"],
            statementIDs: ["statement-1"],
            summary: "Committed one evidence-backed memory.",
            createdAt: now.addingTimeInterval(20)
        ))
        let center = GraphMemoryProductizationCenter(
            candidateRepository: AppGraphWriteCandidateRepository(store: store),
            holdQueueRepository: AppGraphAdmissionHoldQueueRepository(store: store),
            changeLogRepository: AppGraphMemoryChangeLogRepository(store: store)
        )

        let dashboard = try center.loadDashboard(limit: 10)

        #expect(dashboard.summary.pendingCandidateCount == 1)
        #expect(dashboard.summary.openHoldCount == 1)
        #expect(dashboard.summary.recentChangeCount == 1)
        #expect(dashboard.cards.map(\.id) == ["hold-missing-evidence", "candidate-low-confidence", "change-1"])
        #expect(dashboard.cards[0].kind == .admissionHold)
        #expect(dashboard.cards[0].severity == .needsReview)
        #expect(dashboard.cards[0].recommendedActions.contains("inspect_evidence"))
        #expect(dashboard.cards[1].kind == .writeCandidate)
        #expect(dashboard.cards[1].sourceIDs == ["episode-1"])
        #expect(dashboard.cards[2].kind == .changeLog)
        #expect(dashboard.cards[2].severity == .success)
    }
    @Test func graphMemoryReviewCenterApprovesAndRejectsCandidatesWithEvents() async throws {
        let store = try phaseFStore()
        let pending = GraphWriteCandidate(
            id: "candidate-approve",
            groupID: "default",
            kind: .createFact,
            proposedByRunID: "session-1",
            rationale: "Approve this memory candidate.",
            confidence: 0.88,
            payloadJSON: "{\"fact\":\"approved\"}",
            status: .pendingReview
        )
        let rejected = GraphWriteCandidate(
            id: "candidate-reject",
            groupID: "default",
            kind: .createFact,
            proposedByRunID: "session-1",
            rationale: "Reject this memory candidate.",
            confidence: 0.20,
            payloadJSON: "{\"fact\":\"rejected\"}",
            status: .pendingReview
        )
        try store.upsertWriteCandidate(pending)
        try store.upsertWriteCandidate(rejected)
        let center = GraphMemoryProductizationCenter(
            candidateRepository: AppGraphWriteCandidateRepository(store: store),
            holdQueueRepository: AppGraphAdmissionHoldQueueRepository(store: store),
            changeLogRepository: AppGraphMemoryChangeLogRepository(store: store)
        )

        let approved = try await center.approveCandidate(id: "candidate-approve", sessionID: "session-1", actor: "tester")
        let rejection = try await center.rejectCandidate(id: "candidate-reject", sessionID: "session-1", reason: "Not grounded enough", actor: "tester")
        let candidates = try AppGraphWriteCandidateRepository(store: store).loadCandidates(limit: 10)

        #expect(candidates.first { $0.id == "candidate-approve" }?.status == .approved)
        #expect(candidates.first { $0.id == "candidate-reject" }?.status == .rejected)
        #expect(approved.event.kind == .graphMemoryHeld)
        #expect(approved.message.contains("approved"))
        #expect(rejection.event.kind == .graphMemoryHeld)
        #expect(rejection.message.contains("rejected"))
        #expect(rejection.card.severity == .error)
    }
}

private func phaseFStore(_ name: String = UUID().uuidString) throws -> SQLiteGraphKernelStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("phase-f-\(name).sqlite")
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return store
}
