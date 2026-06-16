import XCTest
@testable import ConnorGraphAppSupport

final class AgentToolInvocationAssemblerTests: XCTestCase {
    func testCombinesRequestedStartedAndFinishedEventsIntoSingleInvocation() throws {
        let events = [
            AgentEventPresentation(
                id: "requested",
                kind: "tool_requested",
                title: "Tool requested: Bash",
                detail: "Call call-1 · Arguments: {\"command\":\"echo hello\"}",
                severity: .info,
                runID: "run-1",
                sessionID: "session-1",
                toolActivity: AgentToolActivityPresentation(
                    id: "activity-requested",
                    callID: "call-1",
                    phase: .requested,
                    rawToolName: "Bash",
                    semanticKind: .shellCommand,
                    title: "Shell",
                    subtitle: nil,
                    target: "echo hello",
                    detail: "{\"command\":\"echo hello\"}",
                    icon: "terminal",
                    severity: .info,
                    argumentsJSON: "{\"command\":\"echo hello\"}",
                    resultJSON: nil
                )
            ),
            AgentEventPresentation(
                id: "started",
                kind: "tool_started",
                title: "Tool running: Bash",
                detail: "Call call-1 is executing.",
                severity: .info,
                runID: "run-1",
                sessionID: "session-1",
                toolActivity: AgentToolActivityPresentation(
                    id: "activity-started",
                    callID: "call-1",
                    phase: .running,
                    rawToolName: "Bash",
                    semanticKind: .shellCommand,
                    title: "Shell",
                    subtitle: "running",
                    target: "echo hello",
                    detail: "running",
                    icon: "terminal",
                    severity: .info,
                    argumentsJSON: nil,
                    resultJSON: nil
                )
            ),
            AgentEventPresentation(
                id: "finished",
                kind: "tool_finished",
                title: "Tool finished: Bash",
                detail: "Call call-1 · stdout:\nhello\n",
                severity: .success,
                runID: "run-1",
                sessionID: "session-1",
                toolActivity: AgentToolActivityPresentation(
                    id: "activity-finished",
                    callID: "call-1",
                    phase: .finished,
                    rawToolName: "Bash",
                    semanticKind: .shellCommand,
                    title: "Shell",
                    subtitle: "done",
                    target: nil,
                    detail: "stdout:\nhello\n",
                    icon: "terminal",
                    severity: .success,
                    argumentsJSON: nil,
                    resultJSON: "{\"stdout\":\"hello\\n\",\"stderr\":\"\",\"exitCode\":0}"
                )
            )
        ]

        let invocations = AgentToolInvocationAssembler().invocations(from: events)

        XCTAssertEqual(invocations.count, 1)
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.callID, "call-1")
        XCTAssertEqual(invocation.runID, "run-1")
        XCTAssertEqual(invocation.sessionID, "session-1")
        XCTAssertEqual(invocation.toolName, "Bash")
        XCTAssertEqual(invocation.phase, .finished)
        XCTAssertEqual(invocation.severity, .success)
        XCTAssertEqual(invocation.argumentsJSON, "{\"command\":\"echo hello\"}")
        XCTAssertEqual(invocation.resultJSON, "{\"stdout\":\"hello\\n\",\"stderr\":\"\",\"exitCode\":0}")
        XCTAssertEqual(invocation.outputText, "stdout:\nhello\n")
        XCTAssertEqual(invocation.requestedEventID, "requested")
        XCTAssertEqual(invocation.startedEventID, "started")
        XCTAssertEqual(invocation.finishedEventID, "finished")
        XCTAssertEqual(invocation.rawEventIDs, ["requested", "started", "finished"])
    }

    func testFailedEventWinsOverFinishedForSameCallID() throws {
        let events = [
            toolEvent(id: "finished", phase: .finished, severity: .success, detail: "partial output"),
            toolEvent(id: "failed", phase: .failed, severity: .error, detail: "permission denied")
        ]

        let invocation = try XCTUnwrap(AgentToolInvocationAssembler().invocations(from: events).first)

        XCTAssertEqual(invocation.phase, .failed)
        XCTAssertEqual(invocation.severity, .error)
        XCTAssertEqual(invocation.errorText, "permission denied")
        XCTAssertEqual(invocation.failedEventID, "failed")
    }

    func testOutOfOrderEventsKeepOriginalCallOrderAndMergeLaterRequestArguments() throws {
        let events = [
            toolEvent(id: "finished-a", callID: "call-a", phase: .finished, severity: .success, detail: "output a"),
            toolEvent(id: "requested-a", callID: "call-a", phase: .requested, severity: .info, detail: "args a", argumentsJSON: "{\"command\":\"pwd\"}"),
            toolEvent(id: "requested-b", callID: "call-b", phase: .requested, severity: .info, detail: "args b", argumentsJSON: "{\"command\":\"ls\"}")
        ]

        let invocations = AgentToolInvocationAssembler().invocations(from: events)

        XCTAssertEqual(invocations.map(\.callID), ["call-a", "call-b"])
        XCTAssertEqual(invocations.first?.argumentsJSON, "{\"command\":\"pwd\"}")
        XCTAssertEqual(invocations.first?.outputText, "output a")
    }

    private func toolEvent(
        id: String,
        callID: String = "call-1",
        phase: AgentToolActivityPhase,
        severity: AgentEventPresentationSeverity,
        detail: String,
        argumentsJSON: String? = nil,
        resultJSON: String? = nil
    ) -> AgentEventPresentation {
        AgentEventPresentation(
            id: id,
            kind: "tool_\(phase.rawValue)",
            title: "Tool \(phase.rawValue): Bash",
            detail: detail,
            severity: severity,
            runID: "run-1",
            sessionID: "session-1",
            toolActivity: AgentToolActivityPresentation(
                id: "activity-\(id)",
                callID: callID,
                phase: phase,
                rawToolName: "Bash",
                semanticKind: .shellCommand,
                title: "Shell",
                subtitle: nil,
                target: nil,
                detail: detail,
                icon: "terminal",
                severity: severity,
                argumentsJSON: argumentsJSON,
                resultJSON: resultJSON
            )
        )
    }
}
