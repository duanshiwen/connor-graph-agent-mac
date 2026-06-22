import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func memoryOSContextCompilerReportsUncertaintyForLowConfidenceItems() {
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = MemoryOSStatement(id: "low", subjectID: "node", predicate: "maybe", text: "Low confidence item", status: .candidate, confidence: 0.3, validAt: now, committedAt: now)

    let contract = MemoryOSContextCompiler().compile(query: "test", statements: [statement], beliefs: [], entities: [], now: now)

    #expect(contract.hasUncertaintySignals)
}
