import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Run interaction ownership")
struct RunInteractionOwnershipTests {
    @MainActor @Test func stopKeepsSessionOwnedUntilRuntimeSettles() {
        let coordinator = ChatRunCoordinator(model: ChatRunModel(), fallbackSession: AgentSession(id: "session"))
        coordinator.acquireExecutionActivity = {
            AppExecutionLease(reason: "test", begin: { _ in NSObject() }, end: { _ in })
        }
        let backend = AnyAgentBackend(InteractionBackend())
        #expect(coordinator.begin(sessionID: "session", backend: backend))
        _ = coordinator.registerRun(sessionID: "session", runID: "run", backend: backend)
        coordinator.cancelActive(sessionID: "session", runID: "run", reason: "stop", backend: backend)
        #expect(coordinator.isActive)
        #expect(!coordinator.begin(sessionID: "session", backend: backend))
        coordinator.finish(sessionID: "session")
        #expect(!coordinator.isActive)
        #expect(coordinator.begin(sessionID: "session", backend: backend))
        coordinator.shutdown()
    }
}
private struct InteractionBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
