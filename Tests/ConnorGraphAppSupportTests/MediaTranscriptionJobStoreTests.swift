import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Media Transcription Job Store Tests")
struct MediaTranscriptionJobStoreTests {
    @Test func storePersistsJobProgressEventsDiagnosticsAndCheckpoints() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = MediaTranscriptionJobStore(paths: paths)
        let now = Date(timeIntervalSince1970: 1_000)
        var job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", detectedAt: now),
            createdAt: now,
            updatedAt: now
        )

        try store.save(job)
        job = try job.transitioning(to: .preparingRuntime, at: now.addingTimeInterval(1))
        try store.save(job)
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: job.id, state: job.state, message: "Runtime preparation started", createdAt: now), sessionID: job.ownerSessionID)
        try store.saveDiagnostics(MediaTranscriptionDiagnostics(jobID: job.id, lastUpdatedAt: now, entries: ["ok"]), sessionID: job.ownerSessionID)
        try store.markCheckpoint("runtime-ready", sessionID: job.ownerSessionID, jobID: job.id, at: now)

        let loaded = try store.load(sessionID: "session-1", jobID: "job-1")
        let events = try store.loadEvents(sessionID: "session-1", jobID: "job-1")
        let directory = store.jobDirectory(sessionID: "session-1", jobID: "job-1")

        #expect(loaded.id == job.id)
        #expect(loaded.ownerSessionID == job.ownerSessionID)
        #expect(loaded.state == .preparingRuntime)
        #expect(loaded.source.pageURLString == "https://example.com/video")
        #expect(events.map(\.message) == ["Runtime preparation started"])
        #expect(store.hasCheckpoint("runtime-ready", sessionID: "session-1", jobID: "job-1"))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("job.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("progress.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("diagnostics.json").path))
    }

    @Test func missingJobThrowsTypedError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaTranscriptionJobStore(paths: AppStoragePaths(applicationSupportDirectory: root))

        #expect(throws: MediaTranscriptionJobStoreError.self) {
            _ = try store.load(sessionID: "session-1", jobID: "missing")
        }
    }
}
