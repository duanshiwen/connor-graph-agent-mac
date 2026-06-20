import Foundation
import ConnorGraphCore

public enum MediaTranscriptionTaskHandlerError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingJobID
    case missingOwnerSessionID
    case runtimeUnhealthy([String])
    case transcriptUnavailable(String)

    public var description: String {
        switch self {
        case .missingJobID: "missingJobID"
        case .missingOwnerSessionID: "missingOwnerSessionID"
        case .runtimeUnhealthy: "Connor 内置媒体运行时尚未就绪，请稍后重试或在设置中更新媒体运行时。"
        case .transcriptUnavailable: "媒体转写未能完成：Connor 内置媒体运行时尚未就绪，或当前网页没有可获取的字幕/音频。"
        }
    }
}

public struct MediaTranscriptionTaskRequest: Sendable, Equatable {
    public var jobID: String
    public var ownerSessionID: String
    public var runID: String?

    public init(jobID: String, ownerSessionID: String, runID: String? = nil) {
        self.jobID = jobID
        self.ownerSessionID = ownerSessionID
        self.runID = runID
    }
}

public struct MediaTranscriptionTaskHandler: Sendable {
    public var store: MediaTranscriptionJobStore
    public var runtimeSupervisor: any MediaRuntimeSupervising
    public var requireHealthyRuntime: Bool

    public init(store: MediaTranscriptionJobStore, runtimeSupervisor: any MediaRuntimeSupervising, requireHealthyRuntime: Bool = false) {
        self.store = store
        self.runtimeSupervisor = runtimeSupervisor
        self.requireHealthyRuntime = requireHealthyRuntime
    }

    public func run(_ request: MediaTranscriptionTaskRequest, now: Date = Date()) async throws -> String {
        var job = try store.load(sessionID: request.ownerSessionID, jobID: request.jobID)
        if job.state.isTerminal {
            return try terminalSummary(for: job)
        }
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: job.id, state: job.state, message: "Media transcription task started", createdAt: now, metadata: ["runID": request.runID ?? ""]), sessionID: job.ownerSessionID)

        job = try transition(job, to: .preparingRuntime, message: "Preparing Connor built-in media runtime", at: now)
        let report = await runtimeSupervisor.healthCheck(now: now)
        job.runtime = report.snapshot
        try store.save(job)
        try store.saveDiagnostics(MediaTranscriptionDiagnostics(jobID: job.id, lastUpdatedAt: now, runtimeSnapshot: report.snapshot, entries: report.diagnostics), sessionID: job.ownerSessionID)
        if requireHealthyRuntime, !report.isHealthy {
            let failed = job.failing(code: .runtimeUnavailable, message: report.diagnostics.joined(separator: "; "), at: now)
            try store.save(failed)
            throw MediaTranscriptionTaskHandlerError.runtimeUnhealthy(report.missingRuntimeIDs)
        }
        try store.markCheckpoint("runtime-ready", sessionID: job.ownerSessionID, jobID: job.id, at: now)

        job = try transition(job, to: .probingMedia, message: "Probing browser media source", at: now)
        try store.markCheckpoint("metadata", sessionID: job.ownerSessionID, jobID: job.id, at: now)

        if job.request.shouldPreferPlatformSubtitles {
            job = try transition(job, to: .acquiringSubtitles, message: "Checking platform subtitles", at: now)
            try store.markCheckpoint("subtitles-checked", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        if job.request.shouldDownloadAudio || job.request.shouldRunLocalTranscription {
            job = try transition(job, to: .acquiringAudio, message: "Preparing audio acquisition", at: now)
            try store.markCheckpoint("audio-acquisition-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
            job = try transition(job, to: .normalizingAudio, message: "Preparing audio normalization", at: now)
            try store.markCheckpoint("audio-normalization-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        if job.request.shouldRunLocalTranscription {
            job = try transition(job, to: .transcribing, message: "Preparing local transcription", at: now)
            try store.markCheckpoint("transcription-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        if job.request.shouldRunSpeakerDiarization {
            job = try transition(job, to: .diarizing, message: "Preparing speaker diarization", at: now)
            try store.markCheckpoint("diarization-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        guard hasTranscriptArtifact(job) else {
            let reason = missingTranscriptReason(for: job, report: report)
            let failed = job.failing(code: .transcriptionFailed, message: reason.userFacingMessage, at: now)
            try store.save(failed)
            try store.appendEvent(MediaTranscriptionJobEvent(jobID: failed.id, state: .failed, message: reason.userFacingMessage, createdAt: now, metadata: ["diagnostics": reason.diagnosticMessage]), sessionID: failed.ownerSessionID)
            throw MediaTranscriptionTaskHandlerError.transcriptUnavailable(reason.diagnosticMessage)
        }

        job = try transition(job, to: .postProcessing, message: "Preparing transcript post-processing", at: now)
        try store.markCheckpoint("post-processing-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        job = try transition(job, to: .writingAttachments, message: "Preparing transcript attachment write", at: now)
        try store.markCheckpoint("attachments-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        job = try transition(job, to: .sendingToSession, message: "Preparing session return prompt", at: now)
        try store.markCheckpoint("session-return-planned", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        job = try transition(job, to: .completed, message: "Media transcription task completed with transcript artifacts", at: now)
        try store.markCheckpoint("completed", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        return "Media transcription job \(job.id) completed for session \(job.ownerSessionID)"
    }

    private func terminalSummary(for job: BrowserMediaTranscriptionJob) throws -> String {
        switch job.state {
        case .completed:
            return "Media transcription job \(job.id) already completed for session \(job.ownerSessionID)"
        case .failed:
            throw MediaTranscriptionTaskHandlerError.transcriptUnavailable(job.lastErrorMessage ?? "Media transcription job \(job.id) already failed")
        case .cancelled:
            throw MediaTranscriptionTaskHandlerError.transcriptUnavailable("Media transcription job \(job.id) was cancelled")
        default:
            return "Media transcription job \(job.id) is \(job.state.rawValue)"
        }
    }

    private func hasTranscriptArtifact(_ job: BrowserMediaTranscriptionJob) -> Bool {
        job.artifacts.transcriptMarkdown != nil || job.artifacts.transcriptText != nil || !job.artifacts.subtitles.isEmpty || !job.artifacts.attachmentIDs.isEmpty
    }

    private func missingTranscriptReason(for job: BrowserMediaTranscriptionJob, report: MediaRuntimeHealthReport) -> (userFacingMessage: String, diagnosticMessage: String) {
        var diagnostics: [String] = []
        if job.request.shouldPreferPlatformSubtitles {
            diagnostics.append("未获取到平台字幕产物")
        }
        if job.request.shouldDownloadAudio || job.request.shouldRunLocalTranscription {
            diagnostics.append("未获取到可转写音频或本地转写产物")
        }
        if !report.missingRuntimeIDs.isEmpty {
            diagnostics.append("App-managed runtime not ready: \(report.missingRuntimeIDs.joined(separator: ", "))")
        }
        if diagnostics.isEmpty {
            diagnostics.append("媒体处理未生成 transcript artifact")
        }
        let userFacing = "Connor 正在准备内置媒体转写能力，或当前网页没有可获取的字幕/音频。请稍后重试；如果持续失败，请在设置中更新媒体运行时。"
        return (userFacing, diagnostics.joined(separator: "；"))
    }

    private func transition(_ job: BrowserMediaTranscriptionJob, to state: MediaTranscriptionJobState, message: String, at date: Date) throws -> BrowserMediaTranscriptionJob {
        var next = try job.transitioning(to: state, at: date)
        next.progress.currentStepDescription = message
        next.progress.fractionCompleted = progressFraction(for: state)
        try store.save(next)
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: next.id, state: state, message: message, createdAt: date), sessionID: next.ownerSessionID)
        return next
    }

    private func progressFraction(for state: MediaTranscriptionJobState) -> Double {
        switch state {
        case .queued: 0
        case .preparingRuntime: 0.08
        case .probingMedia: 0.16
        case .acquiringSubtitles: 0.24
        case .acquiringAudio: 0.36
        case .normalizingAudio: 0.48
        case .transcribing: 0.62
        case .diarizing: 0.72
        case .postProcessing: 0.82
        case .writingAttachments: 0.9
        case .sendingToSession: 0.96
        case .completed: 1
        case .failed, .cancelled: 1
        }
    }
}
