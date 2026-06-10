import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryJobDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphJobV3PersistsAndLoadsJob() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    let job = GraphJobV3(
        id: "job-1",
        graphID: "default",
        type: .extraction,
        priority: 10,
        payload: ["episode_id": "episode-1"],
        createdAt: Date(timeIntervalSince1970: 1_000),
        nextRunAt: Date(timeIntervalSince1970: 1_005)
    )

    try store.upsert(job: job)
    let loaded = try #require(try store.job(id: job.id))

    #expect(loaded.id == job.id)
    #expect(loaded.status == .queued)
    #expect(loaded.type == .extraction)
    #expect(loaded.priority == 10)
    #expect(loaded.payload["episode_id"] == "episode-1")
}

@Test func graphJobV3ListsRunnableJobsByPriorityAndNextRunAt() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.upsert(job: GraphJobV3(id: "low", graphID: "default", type: .indexRefresh, priority: 1, nextRunAt: Date(timeIntervalSince1970: 1_000)))
    try store.upsert(job: GraphJobV3(id: "high", graphID: "default", type: .indexRefresh, priority: 10, nextRunAt: Date(timeIntervalSince1970: 1_000)))
    try store.upsert(job: GraphJobV3(id: "future", graphID: "default", type: .indexRefresh, priority: 100, nextRunAt: Date(timeIntervalSince1970: 2_000)))
    try store.upsert(job: GraphJobV3(id: "other-graph", graphID: "other", type: .indexRefresh, priority: 100, nextRunAt: Date(timeIntervalSince1970: 1_000)))

    let runnable = try store.runnableJobs(graphID: "default", at: Date(timeIntervalSince1970: 1_000), limit: 10)

    #expect(runnable.map(\.id) == ["high", "low"])
}

@Test func graphJobV3DoesNotListPausedOrRunningJobsAsRunnable() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.upsert(job: GraphJobV3(id: "queued", graphID: "default", type: .indexRefresh, status: .queued, nextRunAt: Date(timeIntervalSince1970: 1_000)))
    try store.upsert(job: GraphJobV3(id: "paused", graphID: "default", type: .indexRefresh, status: .paused, nextRunAt: Date(timeIntervalSince1970: 1_000)))
    try store.upsert(job: GraphJobV3(id: "running", graphID: "default", type: .indexRefresh, status: .running, nextRunAt: Date(timeIntervalSince1970: 1_000)))

    let runnable = try store.runnableJobs(graphID: "default", at: Date(timeIntervalSince1970: 1_000), limit: 10)

    #expect(runnable.map(\.id) == ["queued"])
}

@Test func graphJobV3UpdatesStatusAndFailureMetadata() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    var job = GraphJobV3(id: "job-1", graphID: "default", type: .extraction, maxAttempts: 2, createdAt: Date(timeIntervalSince1970: 1_000), nextRunAt: Date(timeIntervalSince1970: 1_000))
    try store.upsert(job: job)

    job.status = .running
    job.startedAt = Date(timeIntervalSince1970: 1_001)
    job.updatedAt = Date(timeIntervalSince1970: 1_001)
    try store.upsert(job: job)

    var loaded = try #require(try store.job(id: "job-1"))
    #expect(loaded.status == .running)
    #expect(loaded.startedAt == Date(timeIntervalSince1970: 1_001))

    loaded.status = .deadLetter
    loaded.attemptCount = 2
    loaded.finishedAt = Date(timeIntervalSince1970: 1_010)
    loaded.errorCode = "rate_limit"
    loaded.errorMessage = "Rate limited"
    loaded.updatedAt = Date(timeIntervalSince1970: 1_010)
    try store.upsert(job: loaded)

    let failed = try #require(try store.job(id: "job-1"))
    #expect(failed.status == .deadLetter)
    #expect(failed.attemptCount == 2)
    #expect(failed.errorCode == "rate_limit")
    #expect(failed.errorMessage == "Rate limited")
}
