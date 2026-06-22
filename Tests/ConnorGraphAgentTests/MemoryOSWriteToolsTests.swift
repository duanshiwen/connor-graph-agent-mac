import Testing
import ConnorGraphAgent

@Test func memoryOSWriteToolsObservationDefaultsToObservedConfidence() {
    let statement = MemoryOSWriteTools().makeObservation(subjectID: "node", predicate: "p", text: "Observation", evidenceSpanIDs: ["span"])
    #expect(statement.assertionKind.rawValue == "observed")
    #expect(statement.confidence == 0.7)
}
