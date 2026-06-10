import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporarySelfHealingDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphKernelStorePersistsAnomaliesAndJobs() throws {
    let store = try SQLiteGraphKernelStore(path: temporarySelfHealingDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let anomaly = GraphAnomaly(
        id: "anomaly-1",
        graphID: "default",
        anomalyType: .directContradiction,
        statementID: "statement-1",
        relatedStatementIDs: ["statement-0"],
        severity: .high,
        status: .open,
        detectedAt: now
    )
    let job = GraphJobV3(
        id: "job-1",
        graphID: "default",
        type: .anomalyResolution,
        status: .queued,
        priority: 10,
        payload: ["anomaly_id": anomaly.id],
        createdAt: now,
        updatedAt: now,
        nextRunAt: now
    )

    try store.upsert(anomaly: anomaly)
    try store.upsert(job: job)

    #expect(try store.anomaly(id: anomaly.id)?.anomalyType == .directContradiction)
    #expect(try store.runnableJobs(graphID: "default", at: now).map(\.id) == [job.id])
}
