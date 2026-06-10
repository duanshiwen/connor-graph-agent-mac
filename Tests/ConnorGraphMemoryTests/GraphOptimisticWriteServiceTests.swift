import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryOptimisticDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func optimisticWriteCommitsValidStatementAndQueuesIndexJobs() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryOptimisticDatabaseURL().path)
    try store.migrate()
    let service = GraphOptimisticWriteService(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let episode = GraphEpisodeV3(id: "episode-1", graphID: "default", sourceType: .manual, title: "source", content: "诗闻 prefers tea", sourceDescription: "test", occurredAt: now, ingestedAt: now)
    let person = GraphEntity(id: "person-shiwen", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let tea = GraphEntity(id: "pref-tea", graphID: "default", name: "tea", entityKind: .lifeObject, scope: .personal, canonicalClassID: "preference")
    let statement = GraphStatement(id: "statement-1", graphID: "default", subjectEntityID: person.id, predicate: .prefers, objectEntityID: tea.id, statementText: "诗闻 prefers tea", validAt: now, committedAt: now, confidence: 0.9, justifications: [GraphJustification(type: .extracted, source: episode.id, strength: 0.9)], sourceEpisodeIDs: [episode.id])

    let result = try service.commit(GraphOptimisticWriteBatch(graphID: "default", episode: episode, entities: [person, tea], statements: [statement], now: now))

    #expect(result.committedEntityIDs.sorted() == [person.id, tea.id].sorted())
    #expect(result.committedStatementIDs == [statement.id])
    #expect(result.rejectedStatements.isEmpty)
    #expect(try store.statement(id: statement.id)?.beliefStatus == .active)
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.type == .indexRefresh })
}

@Test func optimisticWriteRejectsHardConstraintViolation() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryOptimisticDatabaseURL().path)
    try store.migrate()
    let service = GraphOptimisticWriteService(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let subject = GraphEntity(id: "subject", graphID: "default", name: "subject", entityKind: .entity, scope: .project)
    let object = GraphEntity(id: "object", graphID: "default", name: "object", entityKind: .entity, scope: .project)
    let invalid = GraphStatement(id: "invalid", graphID: "default", subjectEntityID: subject.id, predicate: .relatedTo, objectEntityID: object.id, statementText: "invalid", validAt: now, invalidAt: now.addingTimeInterval(-1), committedAt: now, justifications: [], sourceEpisodeIDs: [])

    let result = try service.commit(GraphOptimisticWriteBatch(graphID: "default", entities: [subject, object], statements: [invalid], now: now))

    #expect(result.committedStatementIDs.isEmpty)
    #expect(result.rejectedStatements.count == 1)
    #expect(try store.statement(id: invalid.id) == nil)
}

@Test func optimisticWriteCommitsContradictionAsAnomalyAndQueuesResolutionJob() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryOptimisticDatabaseURL().path)
    try store.migrate()
    let service = GraphOptimisticWriteService(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let person = GraphEntity(id: "person-shiwen", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let tea = GraphEntity(id: "pref-tea", graphID: "default", name: "tea", entityKind: .lifeObject, scope: .personal)
    let yes = GraphStatement(id: "yes", graphID: "default", subjectEntityID: person.id, predicate: .prefers, objectEntityID: tea.id, statementText: "诗闻 prefers tea", validAt: now, committedAt: now, confidence: 0.9, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.9)], sourceEpisodeIDs: ["episode-1"])
    let no = GraphStatement(id: "no", graphID: "default", subjectEntityID: person.id, predicate: .dislikes, objectEntityID: tea.id, statementText: "诗闻 dislikes tea", validAt: now, committedAt: now, confidence: 0.9, justifications: [GraphJustification(type: .userStated, source: "test", strength: 0.9)], sourceEpisodeIDs: ["episode-2"])

    _ = try service.commit(GraphOptimisticWriteBatch(graphID: "default", entities: [person, tea], statements: [yes], now: now))
    let result = try service.commit(GraphOptimisticWriteBatch(graphID: "default", entities: [], statements: [no], now: now))

    #expect(result.committedStatementIDs == [no.id])
    #expect(result.anomalyIDs.count == 1)
    #expect(try store.statement(id: no.id)?.beliefStatus == .anomaly)
    #expect((try store.statement(id: no.id)?.confidence ?? 1) < 0.9)
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.type == .anomalyResolution })
}
