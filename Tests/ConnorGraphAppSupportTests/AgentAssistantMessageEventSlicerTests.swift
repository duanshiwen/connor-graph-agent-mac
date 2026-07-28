import Testing
import ConnorGraphAppSupport

@Test func assistantMessageEventSlicerPartitionsToolsBetweenAssistantMessages() {
    let events = [
        presentation(id: "run", kind: "runStarted"),
        presentation(id: "tool-1", kind: "toolFinished"),
        presentation(id: "boundary-1", kind: "assistantMessageCreated", assistantMessageID: "progress-1"),
        presentation(id: "tool-2", kind: "toolFinished"),
        presentation(id: "boundary-2", kind: "assistantMessageCreated", assistantMessageID: "progress-2"),
        presentation(id: "tool-3", kind: "toolFinished"),
        presentation(id: "complete", kind: "runCompleted")
    ]
    let slicer = AgentAssistantMessageEventSlicer()

    #expect(slicer.events(forAssistantMessageID: "progress-1", from: events).map(\.id) == ["run", "tool-1"])
    #expect(slicer.events(forAssistantMessageID: "progress-2", from: events).map(\.id) == ["tool-2"])
    #expect(slicer.events(forAssistantMessageID: "final", from: events).map(\.id) == ["tool-3", "complete"])
}

@Test func assistantMessageEventSlicerPreservesLegacyRunWithoutBoundaries() {
    let events = [presentation(id: "tool", kind: "toolFinished")]
    #expect(AgentAssistantMessageEventSlicer().events(forAssistantMessageID: "final", from: events) == events)
}

private func presentation(id: String, kind: String, assistantMessageID: String? = nil) -> AgentEventPresentation {
    AgentEventPresentation(
        id: id,
        kind: kind,
        title: kind,
        detail: kind,
        severity: .success,
        runID: "run",
        sessionID: "session",
        assistantMessageID: assistantMessageID
    )
}
