import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryJobDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphJobQueueEnqueuesAndLeasesRunnableJob() throws {
    let store = try SQLiteGraphStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    let job = GraphJob(id: "job-1", groupID: "default", type: .generateGraphFromEpisode, payload: ["episode_id": "episode-1"])

    try store.enqueue(job: job)
    let leased = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 1_000), leaseDuration: 30))

    #expect(leased.id == job.id)
    #expect(leased.status == .running)
    #expect(leased.leaseOwner == "worker-1")
    #expect(leased.leaseExpiresAt == Date(timeIntervalSince1970: 1_030))
}

@Test func graphJobQueueCompletesLeasedJob() throws {
    let store = try SQLiteGraphStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.enqueue(job: GraphJob(id: "job-1", groupID: "default", type: .generateGraphFromEpisode))
    _ = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 1_000), leaseDuration: 30))

    try store.completeGraphJob(id: "job-1", now: Date(timeIntervalSince1970: 1_010))
    let loaded = try #require(try store.graphJob(id: "job-1"))

    #expect(loaded.status == .succeeded)
    #expect(loaded.finishedAt == Date(timeIntervalSince1970: 1_010))
}

@Test func graphJobQueueDoesNotLeasePausedJobsUntilResumed() throws {
    let store = try SQLiteGraphStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.enqueue(job: GraphJob(id: "job-1", groupID: "default", type: .generateGraphFromEpisode))

    try store.pauseGraphJob(id: "job-1")
    #expect(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(), leaseDuration: 30) == nil)

    try store.resumeGraphJob(id: "job-1", now: Date(timeIntervalSince1970: 2_000))
    let leased = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 2_000), leaseDuration: 30))
    #expect(leased.id == "job-1")
}

@Test func graphJobQueueRecoversExpiredLeases() throws {
    let store = try SQLiteGraphStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.enqueue(job: GraphJob(id: "job-1", groupID: "default", type: .generateGraphFromEpisode))
    _ = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 1_000), leaseDuration: 30))

    try store.recoverExpiredGraphJobLeases(now: Date(timeIntervalSince1970: 1_031))
    let leasedAgain = try #require(try store.leaseNextGraphJob(workerID: "worker-2", now: Date(timeIntervalSince1970: 1_032), leaseDuration: 30))

    #expect(leasedAgain.id == "job-1")
    #expect(leasedAgain.status == .running)
    #expect(leasedAgain.leaseOwner == "worker-2")
}

@Test func graphJobQueueRetriesFailureWithBackoffThenDeadLetters() throws {
    let store = try SQLiteGraphStore(path: temporaryJobDatabaseURL().path)
    try store.migrate()
    try store.enqueue(job: GraphJob(id: "job-1", groupID: "default", type: .generateGraphFromEpisode, maxAttempts: 2))
    _ = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 1_000), leaseDuration: 30))

    try store.failGraphJob(id: "job-1", errorCode: "rate_limit", message: "Rate limited", now: Date(timeIntervalSince1970: 1_001), retryDelay: 60)
    var loaded = try #require(try store.graphJob(id: "job-1"))
    #expect(loaded.status == .queued)
    #expect(loaded.attemptCount == 1)
    #expect(loaded.nextRunAt == Date(timeIntervalSince1970: 1_061))

    _ = try #require(try store.leaseNextGraphJob(workerID: "worker-1", now: Date(timeIntervalSince1970: 1_061), leaseDuration: 30))
    try store.failGraphJob(id: "job-1", errorCode: "rate_limit", message: "Rate limited again", now: Date(timeIntervalSince1970: 1_062), retryDelay: 60)
    loaded = try #require(try store.graphJob(id: "job-1"))
    #expect(loaded.status == .deadLetter)
    #expect(loaded.attemptCount == 2)
}
