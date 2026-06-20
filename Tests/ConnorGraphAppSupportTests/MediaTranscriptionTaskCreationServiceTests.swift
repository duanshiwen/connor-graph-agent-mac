import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Media Transcription Task Creation Service Tests")
struct MediaTranscriptionTaskCreationServiceTests {
    @Test func serviceCreatesSessionOwnedJobAndRecoverableGlobalTask() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let jobStore = MediaTranscriptionJobStore(paths: paths)
        let taskRepository = AppTaskManagementRepository(storagePaths: paths)
        let service = MediaTranscriptionTaskCreationService(jobStore: jobStore, taskRepository: taskRepository)
        let source = BrowserMediaSourceSnapshot(
            pageURLString: "https://example.com/watch",
            pageTitle: "Example Watch",
            mediaElements: [BrowserDetectedMediaElement(id: "video-0", kind: "video")]
        )
        let now = Date(timeIntervalSince1970: 100)

        let result = try service.createTask(ownerSessionID: "session-1", source: source, now: now)
        let loadedJob = try jobStore.load(sessionID: "session-1", jobID: result.job.id)
        let loadedTask = try #require(try taskRepository.loadTask(id: result.task.id))
        let events = try jobStore.loadEvents(sessionID: "session-1", jobID: result.job.id)

        #expect(loadedJob.ownerSessionID == "session-1")
        #expect(loadedJob.source.hasDetectedMedia)
        #expect(loadedTask.metadata.scope == .global)
        #expect(loadedTask.metadata.ownerSessionID == "session-1")
        #expect(loadedTask.metadata.isRecoverable)
        #expect(loadedTask.metadata.recoveryPolicy == .restoreIfQueuedOrRunning)
        #expect(loadedTask.target.targetKind == "media.transcription")
        #expect(loadedTask.lifecycle.nextRunAt == now)
        #expect(events.map(\.state) == [.queued])
    }

    @Test func taskManagementStackExposesCreationHelper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let stack = TaskManagementStack(repository: AppTaskManagementRepository(storagePaths: paths))

        let result = try stack.createMediaTranscriptionTask(
            ownerSessionID: "session-2",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/audio", pageTitle: "Audio"),
            request: MediaTranscriptionRequest(shouldRunSpeakerDiarization: true),
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(result.job.request.shouldRunSpeakerDiarization)
        #expect(try stack.task(id: result.task.id)?.target.parameters["jobID"] == result.job.id)
    }
}
