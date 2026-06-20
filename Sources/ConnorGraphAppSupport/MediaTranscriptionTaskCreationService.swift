import Foundation
import ConnorGraphCore

public struct MediaTranscriptionTaskCreationResult: Sendable, Equatable {
    public var job: BrowserMediaTranscriptionJob
    public var task: ConnorTaskDefinition

    public init(job: BrowserMediaTranscriptionJob, task: ConnorTaskDefinition) {
        self.job = job
        self.task = task
    }
}

public struct MediaTranscriptionTaskCreationService: Sendable {
    public var jobStore: MediaTranscriptionJobStore
    public var taskRepository: AppTaskManagementRepository

    public init(jobStore: MediaTranscriptionJobStore, taskRepository: AppTaskManagementRepository) {
        self.jobStore = jobStore
        self.taskRepository = taskRepository
    }

    @discardableResult
    public func createTask(
        ownerSessionID: String,
        source: BrowserMediaSourceSnapshot,
        request: MediaTranscriptionRequest = MediaTranscriptionRequest(),
        now: Date = Date()
    ) throws -> MediaTranscriptionTaskCreationResult {
        let jobID = "media-job-\(UUID().uuidString.lowercased())"
        let job = BrowserMediaTranscriptionJob(
            id: jobID,
            ownerSessionID: ownerSessionID,
            source: source,
            request: request,
            createdAt: now,
            updatedAt: now
        )
        try jobStore.save(job)
        try jobStore.appendEvent(MediaTranscriptionJobEvent(jobID: jobID, state: .queued, message: "Media transcription job queued", createdAt: now), sessionID: ownerSessionID)

        let task = ConnorTaskDefinition(
            id: "media.transcription.\(jobID)",
            name: Self.taskName(for: source),
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: now, recurrence: .once),
            target: .mediaTranscriptionRun(jobID: jobID, ownerSessionID: ownerSessionID),
            lifecycle: ConnorTaskLifecycle(status: .active, nextRunAt: now),
            metadata: ConnorTaskMetadata(
                createdBySessionID: ownerSessionID,
                rationale: "Transcribe browser media into a session-owned attachment",
                tags: ["media", "transcription", "browser"],
                scope: .global,
                ownerSessionID: ownerSessionID,
                isRecoverable: true,
                recoveryPolicy: .restoreIfQueuedOrRunning,
                isProtectedSystemTask: false,
                userEditableFields: [.name, .tags, .rationale]
            ),
            createdAt: now,
            updatedAt: now
        )
        try taskRepository.saveTask(task)
        return MediaTranscriptionTaskCreationResult(job: job, task: task)
    }

    public static func taskName(for source: BrowserMediaSourceSnapshot) -> String {
        let title = source.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty { return "转写媒体：\(title)" }
        if let host = URL(string: source.pageURLString)?.host, !host.isEmpty { return "转写媒体：\(host)" }
        return "转写浏览器媒体"
    }
}

public extension TaskManagementStack {
    @discardableResult
    func createMediaTranscriptionTask(
        ownerSessionID: String,
        source: BrowserMediaSourceSnapshot,
        request: MediaTranscriptionRequest = MediaTranscriptionRequest(),
        now: Date = Date()
    ) throws -> MediaTranscriptionTaskCreationResult {
        let service = MediaTranscriptionTaskCreationService(
            jobStore: MediaTranscriptionJobStore(paths: repository.storagePaths),
            taskRepository: repository
        )
        return try service.createTask(ownerSessionID: ownerSessionID, source: source, request: request, now: now)
    }
}
