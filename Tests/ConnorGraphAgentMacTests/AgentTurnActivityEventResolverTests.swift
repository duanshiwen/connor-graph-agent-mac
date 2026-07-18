import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Test func liveTurnEventsTakePriorityOverPreviouslyLoadedSnapshot() {
    let loadedEvents = [event(id: "call-1"), event(id: "call-2")]
    let liveEvents = loadedEvents + [event(id: "call-3"), event(id: "call-4")]

    let resolved = AgentTurnActivityEventResolver.events(
        initialEvents: liveEvents,
        loadedEvents: loadedEvents
    )

    #expect(resolved?.map(\.id) == ["call-1", "call-2", "call-3", "call-4"])
}

@Test func loadedSnapshotRemainsAvailableForHistoricalTurn() {
    let loadedEvents = [event(id: "call-1"), event(id: "call-2")]

    let resolved = AgentTurnActivityEventResolver.events(
        initialEvents: nil,
        loadedEvents: loadedEvents
    )

    #expect(resolved?.map(\.id) == ["call-1", "call-2"])
}

private func event(id: String) -> AgentEventPresentation {
    AgentEventPresentation(
        id: id,
        kind: "toolRequested",
        title: "Tool requested",
        detail: id,
        severity: .info
    )
}
