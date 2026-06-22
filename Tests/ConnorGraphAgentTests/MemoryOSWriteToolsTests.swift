import Testing
import ConnorGraphAgent

@Test func memoryOSWriteToolsObservationDefaultsToObservedConfidence() {
    let statement = MemoryOSWriteTools().makeObservation(subjectID: "node", predicate: "p", text: "Observation", evidenceSpanIDs: ["span"])
    #expect(statement.status.rawValue == "observed")
    #expect(statement.confidence == 0.7)
}
