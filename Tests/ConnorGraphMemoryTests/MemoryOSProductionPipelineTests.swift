import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSProcessingPipelineRejectsTemporalStatementWithoutEvidenceBeforeWrite() {
    let statement = MemoryOSStatement(subjectID: "node", predicate: "claims", text: "Invalid because evidence is missing.")
    let issues = MemoryOSStatementValidator().validate(statement)
    #expect(!issues.isEmpty)
}

@Test func memoryOSProcessingPipelineAcceptsEvidenceBackedTemporalStatement() {
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = MemoryOSStatement(subjectID: "node", predicate: "claims", text: "Evidence is present.", assertionKind: .observed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span"])
    let issues = MemoryOSStatementValidator().validate(statement)
    #expect(issues.isEmpty)
}
