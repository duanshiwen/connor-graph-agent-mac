import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryResolverDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func optimisticWriteResolvesIncomingEntityToExistingStableKeyMatch() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryResolverDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let existingPerson = GraphEntity(id: "person-existing", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let tea = GraphEntity(id: "tea", graphID: "default", name: "tea", entityKind: .lifeObject, scope: .personal)
    try store.upsert(entity: existingPerson)
    try store.upsert(entity: tea)

    let incomingPerson = GraphEntity(id: "person-incoming", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let statement = GraphStatement(id: "statement", graphID: "default", subjectEntityID: incomingPerson.id, predicate: .prefers, objectEntityID: tea.id, statementText: "诗闻 prefers tea", validAt: now, committedAt: now, justifications: [GraphJustification(type: .extracted, source: "episode", strength: 0.8)], sourceEpisodeIDs: ["episode"])

    let result = try GraphOptimisticWriteService(store: store).commit(GraphOptimisticWriteBatch(graphID: "default", entities: [incomingPerson], statements: [statement], now: now))

    #expect(result.committedEntityIDs.isEmpty)
    #expect(result.resolvedEntityIDs[incomingPerson.id] == existingPerson.id)
    #expect(try store.entity(id: incomingPerson.id) == nil)
    #expect(try store.statement(id: statement.id)?.subjectEntityID == existingPerson.id)
}

@Test func optimisticWriteQueuesEntityMergeReviewForPotentialDuplicate() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryResolverDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    try store.upsert(entity: GraphEntity(id: "agent-os-existing", graphID: "default", name: "Agent OS", entityKind: .workObject, scope: .project, summary: "local agent operating system"))
    let incoming = GraphEntity(id: "agent-os-incoming", graphID: "default", name: "Agent OS Project", entityKind: .workObject, scope: .project, summary: "Agent OS project")

    let result = try GraphOptimisticWriteService(store: store).commit(GraphOptimisticWriteBatch(graphID: "default", entities: [incoming], statements: [], now: now))

    #expect(result.committedEntityIDs == [incoming.id])
    #expect(result.potentialDuplicateEntityIDs[incoming.id] == "agent-os-existing")
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { job in
        job.type == .entityMergeReview && job.payload["incoming_entity_id"] == incoming.id && job.payload["existing_entity_id"] == "agent-os-existing"
    })
}
