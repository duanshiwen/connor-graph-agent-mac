import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func contradictionDetectorFindsMutuallyExclusivePreferencePredicates() {
    let now = Date(timeIntervalSince1970: 1_000)
    let existing = GraphStatement(id: "existing", graphID: "default", subjectEntityID: "person", predicate: .prefers, objectEntityID: "tea", statementText: "prefers tea", validAt: now, confidence: 0.9, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.9)], sourceEpisodeIDs: ["episode-1"])
    let incoming = GraphStatement(id: "incoming", graphID: "default", subjectEntityID: "person", predicate: .dislikes, objectEntityID: "tea", statementText: "dislikes tea", validAt: now, confidence: 0.9, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.9)], sourceEpisodeIDs: ["episode-2"])

    let detector = GraphContradictionDetector()
    let conflicts = detector.detect(incoming: incoming, existingActiveStatements: [existing])

    #expect(conflicts.count == 1)
    #expect(conflicts.first?.existingStatementID == existing.id)
    #expect(conflicts.first?.type == .directContradiction)
}
