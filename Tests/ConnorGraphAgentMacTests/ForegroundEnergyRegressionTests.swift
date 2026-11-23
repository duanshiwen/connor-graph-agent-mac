import AppKit
import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Foreground energy regressions")
struct ForegroundEnergyRegressionTests {
    @Test func textTokensDoNotRestartActivityBuilds() {
        var events = [event("started", kind: "runStarted")]
        let initial = key(events)
        for index in 0..<1_000 {
            events.append(event("token-\(index)", kind: "textDelta"))
            #expect(key(events) == initial)
        }
        // Rebuilding the header is independent of retaining the complete trace.
        #expect(events.count == 1_001)
    }

    @Test(arguments: ["toolRequested", "toolApproved", "toolStarted", "toolProgress", "toolFinished", "toolFailed",
                      "permissionRequested", "permissionResolved", "compactionStarted", "compactionCompleted",
                      "compactionFailed", "runFailed", "runCompleted", "textComplete", "assistantMessageCreated"])
    func activityChangesStillRestartPresentation(kind: String) {
        let events = [event("started", kind: "runStarted"), event("token", kind: "textDelta")]
        #expect(key(events + [event("changed", kind: kind)]) != key(events))
    }

    @Test func disclosureProcessAndHistoryChangesStillRestartPresentation() {
        let events = [event("started", kind: "runStarted")]
        #expect(key(events, expanded: true) != key(events))
        #expect(key(events, state: .completed) != key(events))
        #expect(key(events, state: .failed) != key(events))
        #expect(key(events, state: .cancelled) != key(events))
        #expect(key(events, processID: "other") != key(events))
        #expect(key(nil) != key([]))
        var changedTurn = key(events)
        changedTurn.turnNumber += 1
        #expect(changedTurn != key(events))
    }

    @Test func exceptionalTokenEventsAreNotSuppressed() {
        let events = [event("started", kind: "runStarted")]
        var failure = event("error", kind: "textDelta")
        failure.severity = .error
        #expect(key(events + [failure]) != key(events))
    }

    @MainActor
    @Test func tokenBurstRetainsEveryEventAndPublishesOneCompleteBatch() async {
        let model = ChatRunModel()
        let coordinator = ChatRunCoordinator(model: model, fallbackSession: AgentSession(id: "session"))
        coordinator.selectedSessionID = { "session" }
        let (batches, continuation) = AsyncStream<[AgentEventPresentation]>.makeStream()
        coordinator.onTimelineChanged = { _, events in continuation.yield(events) }
        let events = (0..<2_000).map { event("token-\($0)", kind: "textDelta") }
        for item in events { coordinator.appendEvent(item, sessionID: "session") }
        #expect(coordinator.timeline(sessionID: "session") == events)
        var iterator = batches.makeAsyncIterator()
        let published = await iterator.next()
        #expect(published == events)
        #expect(model.eventTimeline == events)
        coordinator.shutdown()
        continuation.finish()
    }

    @MainActor
    @Test func finalSnapshotCancelsPendingBatchWithoutDuplicatePublication() async throws {
        let model = ChatRunModel()
        let coordinator = ChatRunCoordinator(model: model, fallbackSession: AgentSession(id: "session"))
        coordinator.selectedSessionID = { "session" }
        var publications = 0
        coordinator.onTimelineChanged = { _, _ in publications += 1 }
        let token = event("token", kind: "textDelta")
        let final = [token, event("done", kind: "runCompleted")]
        coordinator.appendEvent(token, sessionID: "session")
        coordinator.setTimeline(final, sessionID: "session")
        try await Task.sleep(for: .milliseconds(120))
        #expect(publications == 1)
        #expect(model.eventTimeline == final)
        #expect(coordinator.timeline(sessionID: "session") == final)
        coordinator.shutdown()
    }

    @MainActor
    @Test func shutdownCancelsPendingUIWork() async throws {
        let coordinator = ChatRunCoordinator(model: ChatRunModel(), fallbackSession: AgentSession(id: "session"))
        var publications = 0
        coordinator.onTimelineChanged = { _, _ in publications += 1 }
        coordinator.appendEvent(event("token", kind: "textDelta"), sessionID: "session")
        coordinator.shutdown()
        try await Task.sleep(for: .milliseconds(120))
        #expect(publications == 0)
    }

    private func key(_ events: [AgentEventPresentation]?, expanded: Bool = false,
                     state: AgentChatTurnProcessState = .running, processID: String = "process") -> AgentTurnActivityLoadKey {
        AgentTurnActivityLoadKey(isExpanded: expanded, processID: processID, processState: state,
                                 turnNumber: 1, events: events)
    }

    private func event(_ id: String, kind: String) -> AgentEventPresentation {
        AgentEventPresentation(id: id, kind: kind, title: kind == "textDelta" ? "Assistant is writing" : kind,
                               detail: "text", severity: .info, runID: "run", sessionID: "session")
    }
}
