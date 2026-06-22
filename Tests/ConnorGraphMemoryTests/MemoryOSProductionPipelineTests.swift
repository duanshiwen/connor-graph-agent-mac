import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSProcessingPipelineRejectsInvalidObservedStatementBeforeWrite() {
    let statement = MemoryOSStatement(subjectID: "node", predicate: "claims", text: "Invalid because evidence is missing.", status: .observed)
    let issues = MemoryOSStatementValidator().validate(statement)
    #expect(!issues.isEmpty)
}

@Test func memoryOSProcessingPipelineAcceptsEvidenceBackedConfirmedStatement() {
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = MemoryOSStatement(subjectID: "node", predicate: "claims", text: "Evidence is present.", status: .confirmed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span"])
    let issues = MemoryOSStatementValidator().validate(statement)
    #expect(issues.isEmpty)
}
