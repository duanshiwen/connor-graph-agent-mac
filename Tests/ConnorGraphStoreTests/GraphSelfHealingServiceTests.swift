import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporarySelfHealingDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func selfHealingDismissesLowerConfidenceAnomalyStatement() throws {
    let store = try SQLiteGraphKernelStore(path: temporarySelfHealingDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let person = GraphEntity(id: "person", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let tea = GraphEntity(id: "tea", graphID: "default", name: "tea", entityKind: .lifeObject, scope: .personal)
    try store.upsert(entity: person)
    try store.upsert(entity: tea)
    try store.upsert(statement: GraphStatement(id: "high", graphID: "default", subjectEntityID: person.id, predicate: .prefers, objectEntityID: tea.id, statementText: "prefers tea", validAt: now, committedAt: now, confidence: 0.9, beliefStatus: .active, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.9)], sourceEpisodeIDs: ["episode-1"]))
    try store.upsert(statement: GraphStatement(id: "low", graphID: "default", subjectEntityID: person.id, predicate: .dislikes, objectEntityID: tea.id, statementText: "dislikes tea", validAt: now, committedAt: now, confidence: 0.3, beliefStatus: .anomaly, justifications: [GraphJustification(type: .extracted, source: "test", strength: 0.3)], sourceEpisodeIDs: ["episode-2"]))
    try store.upsert(anomaly: GraphAnomaly(id: "anomaly-1", graphID: "default", anomalyType: .directContradiction, statementID: "low", relatedStatementIDs: ["high"], severity: .high, status: .open, detectedAt: now))
    try store.upsert(job: GraphJobV3(id: "job-1", graphID: "default", type: .anomalyResolution, payload: ["anomaly_id": "anomaly-1"], createdAt: now, nextRunAt: now))

    let result = try GraphSelfHealingService(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .dismissedIncoming)
    #expect(try store.statement(id: "low")?.beliefStatus == .dismissed)
    #expect(try store.statement(id: "high")?.beliefStatus == .active)
    #expect(try store.anomaly(id: "anomaly-1")?.status == .resolved)
}

@Test func selfHealingSupersedesLowerConfidenceExistingStatement() throws {
    let store = try SQLiteGraphKernelStore(path: temporarySelfHealingDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let person = GraphEntity(id: "person", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let tea = GraphEntity(id: "tea", graphID: "default", name: "tea", entityKind: .lifeObject, scope: .personal)
    try store.upsert(entity: person)
    try store.upsert(entity: tea)
    try store.upsert(statement: GraphStatement(id: "low-existing", graphID: "default", subjectEntityID: person.id, predicate: .prefers, objectEntityID: tea.id, statementText: "prefers tea", validAt: now, committedAt: now, confidence: 0.3, beliefStatus: .active, justifications: [GraphJustification(type: .extracted, source: "test", strength: 0.3)], sourceEpisodeIDs: ["episode-1"]))
    try store.upsert(statement: GraphStatement(id: "high-incoming", graphID: "default", subjectEntityID: person.id, predicate: .dislikes, objectEntityID: tea.id, statementText: "dislikes tea", validAt: now, committedAt: now, confidence: 0.85, beliefStatus: .anomaly, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.85)], sourceEpisodeIDs: ["episode-2"]))
    try store.upsert(anomaly: GraphAnomaly(id: "anomaly-2", graphID: "default", anomalyType: .directContradiction, statementID: "high-incoming", relatedStatementIDs: ["low-existing"], severity: .high, status: .open, detectedAt: now))
    try store.upsert(job: GraphJobV3(id: "job-2", graphID: "default", type: .anomalyResolution, payload: ["anomaly_id": "anomaly-2"], createdAt: now, nextRunAt: now))

    let result = try GraphSelfHealingService(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .acceptedIncoming)
    #expect(try store.statement(id: "high-incoming")?.beliefStatus == .active)
    #expect(try store.statement(id: "low-existing")?.beliefStatus == .superseded)
    #expect(try store.statement(id: "low-existing")?.invalidatedByStatementID == "high-incoming")
    #expect(try store.anomaly(id: "anomaly-2")?.status == .resolved)
}
