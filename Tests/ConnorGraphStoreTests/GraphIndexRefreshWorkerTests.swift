import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryIndexRefreshDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func indexRefreshWorkerRefreshesEntityFTSAndMarksJobSucceeded() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryIndexRefreshDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let entity = GraphEntity(id: "entity-1", graphID: "default", name: "Shiwen Graph Kernel", entityKind: .workObject, scope: .project)
    try store.upsert(entity: entity)
    try store.upsert(job: GraphJobV3(id: "job-index-entity-1", graphID: "default", type: .indexRefresh, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": entity.id], createdAt: now, nextRunAt: now))

    let result = try GraphIndexRefreshWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .refreshed)
    #expect(result?.ownerType == .entity)
    #expect(try store.searchEntitiesFTS(query: "Kernel", graphID: "default", limit: 5).map(\.id).contains(entity.id))
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-index-entity-1" } == false)
}

@Test func indexRefreshWorkerRefreshesStatementFTSAndMarksJobSucceeded() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryIndexRefreshDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let person = GraphEntity(id: "person", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal)
    let project = GraphEntity(id: "project", graphID: "default", name: "Connor Graph Agent", entityKind: .workObject, scope: .project)
    try store.upsert(entity: person)
    try store.upsert(entity: project)
    let statement = GraphStatement(id: "statement-1", graphID: "default", subjectEntityID: person.id, predicate: .developedBy, objectEntityID: project.id, statementText: "Connor Graph Agent kernel index refresh statement", validAt: now, committedAt: now, justifications: [GraphJustification(type: .extracted, source: "test", strength: 0.8)], sourceEpisodeIDs: ["episode"])
    try store.upsert(statement: statement)
    try store.upsert(job: GraphJobV3(id: "job-index-statement-1", graphID: "default", type: .indexRefresh, payload: ["owner_type": GraphIndexOwnerType.statement.rawValue, "owner_id": statement.id], createdAt: now, nextRunAt: now))

    let result = try GraphIndexRefreshWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .refreshed)
    #expect(result?.ownerType == .statement)
    #expect(try store.searchStatementsFTS(query: "refresh", graphID: "default", limit: 5).map(\.id).contains(statement.id))
}

@Test func indexRefreshWorkerMarksJobFailedWhenOwnerMissing() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryIndexRefreshDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    try store.upsert(job: GraphJobV3(id: "job-missing", graphID: "default", type: .indexRefresh, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": "missing"], createdAt: now, nextRunAt: now))

    let result = try GraphIndexRefreshWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .failed)
}
