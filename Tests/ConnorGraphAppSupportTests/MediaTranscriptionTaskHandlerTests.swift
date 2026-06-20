import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Media Transcription Task Handler Tests")
struct MediaTranscriptionTaskHandlerTests {
    @Test func handlerFailsWhenNoTranscriptArtifactIsProduced() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = MediaTranscriptionJobStore(paths: paths)
        let job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video")
        )
        try store.save(job)
        let report = MediaRuntimeHealthReport(
            snapshot: MediaRuntimeSnapshot(
                python: MediaRuntimeComponentSnapshot(id: "python", isAvailable: false),
                ytDLP: MediaRuntimeComponentSnapshot(id: "yt-dlp", isAvailable: false),
                ffmpeg: MediaRuntimeComponentSnapshot(id: "ffmpeg", isAvailable: false),
                whisperKit: MediaRuntimeComponentSnapshot(id: "whisperkit", isAvailable: false)
            ),
            missingRuntimeIDs: ["python", "yt-dlp", "ffmpeg", "whisperkit"],
            diagnostics: ["missing"]
        )
        let handler = MediaTranscriptionTaskHandler(store: store, runtimeSupervisor: FakeMediaRuntimeSupervisor(report: report), requireHealthyRuntime: false)

        await #expect(throws: MediaTranscriptionTaskHandlerError.self) {
            _ = try await handler.run(MediaTranscriptionTaskRequest(jobID: "job-1", ownerSessionID: "session-1", runID: "run-1"), now: Date(timeIntervalSince1970: 0))
        }
        let loaded = try store.load(sessionID: "session-1", jobID: "job-1")
        let events = try store.loadEvents(sessionID: "session-1", jobID: "job-1")

        #expect(loaded.state == .failed)
        #expect(loaded.lastErrorCode == .transcriptionFailed)
        #expect(loaded.lastErrorMessage?.contains("Connor 正在准备内置媒体转写能力") == true)
        #expect(loaded.lastErrorMessage?.contains("yt-dlp") == false)
        #expect(loaded.lastErrorMessage?.contains("ffmpeg") == false)
        #expect(store.hasCheckpoint("runtime-ready", sessionID: "session-1", jobID: "job-1"))
        #expect(!store.hasCheckpoint("completed", sessionID: "session-1", jobID: "job-1"))
        #expect(events.contains { $0.state == .preparingRuntime })
        #expect(events.contains { $0.state == .failed })
    }

    @Test func handlerDoesNotRerunTerminalFailedJobs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaTranscriptionJobStore(paths: AppStoragePaths(applicationSupportDirectory: root))
        let failed = BrowserMediaTranscriptionJob(
            id: "job-terminal",
            ownerSessionID: "session-terminal",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video")
        ).failing(code: .transcriptionFailed, message: "Connor 正在准备内置媒体转写能力", at: Date(timeIntervalSince1970: 0))
        try store.save(failed)
        let handler = MediaTranscriptionTaskHandler(
            store: store,
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot())),
            requireHealthyRuntime: false
        )

        await #expect(throws: MediaTranscriptionTaskHandlerError.self) {
            _ = try await handler.run(MediaTranscriptionTaskRequest(jobID: "job-terminal", ownerSessionID: "session-terminal"))
        }
        let loaded = try store.load(sessionID: "session-terminal", jobID: "job-terminal")
        #expect(loaded.state == .failed)
        #expect(loaded.lastErrorCode == .transcriptionFailed)
    }

    @Test func handlerCanFailFastWhenRuntimeHealthIsRequired() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaTranscriptionJobStore(paths: AppStoragePaths(applicationSupportDirectory: root))
        let job = BrowserMediaTranscriptionJob(id: "job-2", ownerSessionID: "session-2", source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video"))
        try store.save(job)
        let handler = MediaTranscriptionTaskHandler(
            store: store,
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot(), missingRuntimeIDs: ["ffmpeg"], diagnostics: ["Missing ffmpeg"])),
            requireHealthyRuntime: true
        )

        await #expect(throws: MediaTranscriptionTaskHandlerError.self) {
            _ = try await handler.run(MediaTranscriptionTaskRequest(jobID: "job-2", ownerSessionID: "session-2"))
        }
        let loaded = try store.load(sessionID: "session-2", jobID: "job-2")
        #expect(loaded.state == .failed)
        #expect(loaded.lastErrorCode == .runtimeUnavailable)
    }
}
