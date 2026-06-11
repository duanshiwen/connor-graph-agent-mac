import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphAppSupport

private func temporaryPhase7Directory(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-phase7-tests", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
}

@Test func graphRetrievalEvaluationRepositoryPersistsCasesAndReportsUnderGraphDirectory() throws {
    let root = temporaryPhase7Directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let repository = AppGraphRetrievalEvaluationRepository(storagePaths: paths)
    let cases = [
        GraphRetrievalEvaluationCase(
            id: "golden-hop",
            queryText: "connect alice to carol",
            graphID: "default",
            judgments: [
                GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-bob-carol", relevance: 2, isRequired: true)
            ],
            tags: ["multi-hop"]
        )
    ]

    try repository.saveCases(cases)
    let loaded = try repository.loadCases()
    let report = GraphRetrievalEvaluationReport(
        generatedAt: Date(timeIntervalSince1970: 1_782_000_000),
        k: 5,
        caseResults: [
            GraphRetrievalEvaluator.evaluate(
                evaluationCase: cases[0],
                response: GraphSearchResponse(hits: [
                    GraphSearchHit(ownerType: .statement, ownerID: "statement-bob-carol", title: "Bridge", text: "Alice Bob Carol", score: 1, retrievalMethod: "graph_neighborhood_hop2_v2")
                ]),
                k: 5
            )
        ]
    )
    let reportURL = try repository.saveReport(report, filename: "report.json")

    #expect(loaded == cases)
    #expect(FileManager.default.fileExists(atPath: repository.manifestURL.path))
    #expect(FileManager.default.fileExists(atPath: reportURL.path))
    #expect(repository.manifestURL.path.contains("/graph/evaluations/"))
    #expect(reportURL.path.contains("/graph/evaluations/reports/"))
    #expect(repository.manifestURL.path.contains("workspace") == false)
}

@Test func graphRetrievalEvaluationRepositoryRejectsDuplicateCasesDuplicateJudgmentsAndEmptyJudgments() throws {
    let root = temporaryPhase7Directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AppGraphRetrievalEvaluationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
    let judgment = GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-one")
    let evaluationCase = GraphRetrievalEvaluationCase(id: "case-one", queryText: "one", graphID: "default", judgments: [judgment])

    #expect(throws: AppGraphRetrievalEvaluationRepositoryError.duplicateCaseID("case-one")) {
        try repository.validate([evaluationCase, evaluationCase])
    }
    #expect(throws: AppGraphRetrievalEvaluationRepositoryError.duplicateJudgmentID(caseID: "case-one", judgmentID: "statement:statement-one")) {
        try repository.validate([
            GraphRetrievalEvaluationCase(id: "case-one", queryText: "one", graphID: "default", judgments: [judgment, judgment])
        ])
    }
    #expect(throws: AppGraphRetrievalEvaluationRepositoryError.emptyJudgments("empty")) {
        try repository.validate([
            GraphRetrievalEvaluationCase(id: "empty", queryText: "empty", graphID: "default", judgments: [])
        ])
    }
}
