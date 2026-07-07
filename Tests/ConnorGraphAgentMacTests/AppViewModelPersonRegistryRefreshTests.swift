import Foundation
import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppViewModelPersonRegistryRefreshTests {
    @Test func agentTurnMutatedPersonRegistryReturnsTrueForSuccessfulContactsWrite() {
        let events = [toolEvent(toolName: "contacts_write", phase: .finished, severity: .success)]

        #expect(AppViewModel.agentTurnMutatedPersonRegistry(events))
    }

    @Test func agentTurnMutatedPersonRegistryIgnoresContactsRead() {
        let events = [toolEvent(toolName: "contacts_read", phase: .finished, severity: .success)]

        #expect(!AppViewModel.agentTurnMutatedPersonRegistry(events))
    }

    @Test func agentTurnMutatedPersonRegistryIgnoresFailedContactsWrite() {
        let events = [toolEvent(toolName: "contacts_write", phase: .failed, severity: .error)]

        #expect(!AppViewModel.agentTurnMutatedPersonRegistry(events))
    }

    @Test func agentTurnMutatedPersonRegistryIgnoresRunningContactsWrite() {
        let events = [toolEvent(toolName: "contacts_write", phase: .running, severity: .info)]

        #expect(!AppViewModel.agentTurnMutatedPersonRegistry(events))
    }

    private func toolEvent(
        toolName: String,
        phase: AgentToolActivityPhase,
        severity: AgentEventPresentationSeverity
    ) -> AgentEventPresentation {
        AgentEventPresentation(
            kind: phase == .finished ? "tool_finished" : "tool_\(phase.rawValue)",
            title: toolName,
            detail: "",
            severity: severity,
            runID: "run-test",
            sessionID: "session-test",
            toolActivity: AgentToolActivityPresentation(
                callID: "call-\(toolName)-\(phase.rawValue)",
                phase: phase,
                rawToolName: toolName,
                semanticKind: .unknown,
                title: toolName,
                icon: "person.crop.circle",
                severity: severity
            )
        )
    }
}
