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
        #expect(loaded.lastErrorMessage?.contains("未获取到平台字幕产物") == true)
        #expect(loaded.lastErrorMessage?.contains("未获取到可转写音频或本地转写产物") == true)
        #expect(loaded.lastErrorMessage?.contains("App-managed runtime not ready") == true)
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

    @Test func handlerDefaultsToWhisperKitLocalTranscriber() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let handler = MediaTranscriptionTaskHandler(
            store: MediaTranscriptionJobStore(paths: AppStoragePaths(applicationSupportDirectory: root)),
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot()))
        )

        #expect(handler.localTranscriber is WhisperKitMediaLocalTranscriber)
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

    @Test func handlerWritesLocalTranscriptionArtifactsWhenAudioIsNormalized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = MediaTranscriptionJobStore(paths: paths)
        let source = BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", pageTitle: "Example Video")
        let job = BrowserMediaTranscriptionJob(id: "job-local-transcription", ownerSessionID: "session-local-transcription", source: source)
        try store.save(job)
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let audioDirectory = jobDirectory.appendingPathComponent("audio/original", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let originalAudio = audioDirectory.appendingPathComponent("source.m4a")
        try Data("audio".utf8).write(to: originalAudio)
        var seeded = try store.load(sessionID: job.ownerSessionID, jobID: job.id)
        seeded.artifacts.originalAudio = MediaTranscriptionArtifactRef(kind: "originalAudio", relativePath: "audio/original/source.m4a", byteCount: 5, createdAt: Date(timeIntervalSince1970: 0))
        try store.save(seeded)

        let handler = MediaTranscriptionTaskHandler(
            store: store,
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot())),
            requireHealthyRuntime: false,
            processRunner: CapturingMediaProcessRunner { invocation in
                if invocation.executable.lastPathComponent == "ffmpeg", let outputPath = invocation.arguments.last {
                    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: outputPath).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? Data("normalized".utf8).write(to: URL(fileURLWithPath: outputPath))
                    return MediaProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
                return MediaProcessResult(exitCode: 1, stdout: "", stderr: "forced no subtitles/audio download")
            },
            localTranscriber: FakeMediaLocalTranscriber(result: MediaLocalTranscriptionResult(plainText: "Hello local transcript", segmentsJSONL: "{\"text\":\"Hello local transcript\"}\n", diagnostics: ["fake local transcription"]))
        )

        let summary = try await handler.run(MediaTranscriptionTaskRequest(jobID: job.id, ownerSessionID: job.ownerSessionID), now: Date(timeIntervalSince1970: 1))
        let loaded = try store.load(sessionID: job.ownerSessionID, jobID: job.id)
        let transcriptPath = jobDirectory.appendingPathComponent(try #require(loaded.artifacts.transcriptText?.relativePath))

        #expect(summary.contains("completed"))
        #expect(loaded.state == .completed)
        #expect(loaded.artifacts.transcriptMarkdown != nil)
        #expect(loaded.artifacts.transcriptText != nil)
        #expect(loaded.artifacts.segmentsJSONL != nil)
        #expect(!loaded.artifacts.attachmentIDs.isEmpty)
        #expect(try String(contentsOf: transcriptPath, encoding: .utf8) == "Hello local transcript")
        #expect(store.hasCheckpoint("local-transcription-completed", sessionID: job.ownerSessionID, jobID: job.id))
    }

    @Test func handlerSurfacesLocalTranscriptionFailureReason() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = MediaTranscriptionJobStore(paths: paths)
        let job = BrowserMediaTranscriptionJob(id: "job-local-failure", ownerSessionID: "session-local-failure", source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video"))
        try store.save(job)
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let audioDirectory = jobDirectory.appendingPathComponent("audio/original", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let originalAudio = audioDirectory.appendingPathComponent("source.m4a")
        try Data("audio".utf8).write(to: originalAudio)
        var seeded = try store.load(sessionID: job.ownerSessionID, jobID: job.id)
        seeded.artifacts.originalAudio = MediaTranscriptionArtifactRef(kind: "originalAudio", relativePath: "audio/original/source.m4a", byteCount: 5, createdAt: Date(timeIntervalSince1970: 0))
        try store.save(seeded)

        let handler = MediaTranscriptionTaskHandler(
            store: store,
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot())),
            requireHealthyRuntime: false,
            processRunner: CapturingMediaProcessRunner { invocation in
                if invocation.executable.lastPathComponent == "ffmpeg", let outputPath = invocation.arguments.last {
                    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: outputPath).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? Data("normalized".utf8).write(to: URL(fileURLWithPath: outputPath))
                    return MediaProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
                return MediaProcessResult(exitCode: 1, stdout: "", stderr: "forced no subtitles/audio download")
            },
            localTranscriber: UnavailableMediaLocalTranscriber(reason: "WhisperKit SDK is not linked")
        )

        await #expect(throws: MediaTranscriptionTaskHandlerError.self) {
            _ = try await handler.run(MediaTranscriptionTaskRequest(jobID: job.id, ownerSessionID: job.ownerSessionID), now: Date(timeIntervalSince1970: 1))
        }
        let loaded = try store.load(sessionID: job.ownerSessionID, jobID: job.id)
        let events = try store.loadEvents(sessionID: job.ownerSessionID, jobID: job.id)

        #expect(loaded.state == .failed)
        #expect(loaded.lastErrorMessage?.contains("本地转写未完成") == true)
        #expect(loaded.lastErrorMessage?.contains("WhisperKit SDK is not linked") == true)
        #expect(events.contains { $0.message.contains("Local transcription failed") })
    }

    @Test func handlerPassesAppManagedFFmpegLocationToYTDLP() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = MediaTranscriptionJobStore(paths: paths)
        let source = BrowserMediaSourceSnapshot(pageURLString: "https://www.youtube.com/watch?v=example")
        let job = BrowserMediaTranscriptionJob(id: "job-ffmpeg-location", ownerSessionID: "session-ffmpeg-location", source: source)
        try store.save(job)
        let recorder = InvocationRecorder()
        let handler = MediaTranscriptionTaskHandler(
            store: store,
            runtimeSupervisor: FakeMediaRuntimeSupervisor(report: MediaRuntimeHealthReport(snapshot: MediaRuntimeSnapshot())),
            requireHealthyRuntime: false,
            processRunner: CapturingMediaProcessRunner { invocation in
                recorder.append(invocation)
                return MediaProcessResult(exitCode: 1, stdout: "", stderr: "forced failure")
            }
        )

        await #expect(throws: MediaTranscriptionTaskHandlerError.self) {
            _ = try await handler.run(MediaTranscriptionTaskRequest(jobID: job.id, ownerSessionID: job.ownerSessionID))
        }

        let ytDLPInvocations = recorder.snapshot().filter { $0.executable.lastPathComponent == "yt-dlp.sh" }
        #expect(!ytDLPInvocations.isEmpty)
        for invocation in ytDLPInvocations {
            #expect(invocation.arguments.contains("--ffmpeg-location"))
            let index = try #require(invocation.arguments.firstIndex(of: "--ffmpeg-location"))
            #expect(invocation.arguments[index + 1] == paths.sidecarsDirectory.appendingPathComponent("ffmpeg/runtime").path)
        }
    }
}

private struct CapturingMediaProcessRunner: MediaProcessRunning {
    var handler: @Sendable (MediaProcessInvocation) -> MediaProcessResult

    func run(_ invocation: MediaProcessInvocation) -> MediaProcessResult {
        handler(invocation)
    }
}

private struct FakeMediaLocalTranscriber: MediaLocalTranscriptionProviding {
    var result: MediaLocalTranscriptionResult

    func transcribe(_ request: MediaLocalTranscriptionRequest) async throws -> MediaLocalTranscriptionResult {
        result
    }
}

private final class InvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [MediaProcessInvocation] = []

    func append(_ invocation: MediaProcessInvocation) {
        lock.lock()
        defer { lock.unlock() }
        invocations.append(invocation)
    }

    func snapshot() -> [MediaProcessInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }
}
