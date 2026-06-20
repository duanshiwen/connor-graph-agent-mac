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

public struct MediaProcessInvocation: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct MediaProcessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol MediaProcessRunning: Sendable {
    func run(_ invocation: MediaProcessInvocation) -> MediaProcessResult
}

public struct DefaultMediaProcessRunner: MediaProcessRunning, Sendable {
    public init() {}

    public func run(_ invocation: MediaProcessInvocation) -> MediaProcessResult {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return MediaProcessResult(exitCode: -1, stdout: "", stderr: String(describing: error))
        }
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return MediaProcessResult(exitCode: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
    }
}

public struct MediaTranscriptionTaskHandler: Sendable {
    public var store: MediaTranscriptionJobStore
    public var runtimeSupervisor: any MediaRuntimeSupervising
    public var requireHealthyRuntime: Bool
    public var processRunner: any MediaProcessRunning
    public var localTranscriber: any MediaLocalTranscriptionProviding

    public init(
        store: MediaTranscriptionJobStore,
        runtimeSupervisor: any MediaRuntimeSupervising,
        requireHealthyRuntime: Bool = false,
        processRunner: any MediaProcessRunning = DefaultMediaProcessRunner(),
        localTranscriber: any MediaLocalTranscriptionProviding = UnavailableMediaLocalTranscriber()
    ) {
        self.store = store
        self.runtimeSupervisor = runtimeSupervisor
        self.requireHealthyRuntime = requireHealthyRuntime
        self.processRunner = processRunner
        self.localTranscriber = localTranscriber
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
            job = try acquirePlatformSubtitles(for: job, at: now)
            try store.markCheckpoint("subtitles-checked", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        if !hasTranscriptArtifact(job), job.request.shouldDownloadAudio || job.request.shouldRunLocalTranscription {
            job = try transition(job, to: .acquiringAudio, message: "Downloading media audio", at: now)
            job = try acquireAudio(for: job, at: now)
            try store.markCheckpoint("audio-acquired", sessionID: job.ownerSessionID, jobID: job.id, at: now)
            job = try transition(job, to: .normalizingAudio, message: "Normalizing audio with ffmpeg", at: now)
            job = try normalizeAudio(for: job, at: now)
            try store.markCheckpoint("audio-normalized", sessionID: job.ownerSessionID, jobID: job.id, at: now)
        }

        if !hasTranscriptArtifact(job), job.request.shouldRunLocalTranscription {
            job = try transition(job, to: .transcribing, message: "Running local transcription", at: now)
            do {
                job = try await runLocalTranscription(for: job, at: now)
                try store.markCheckpoint("local-transcription-completed", sessionID: job.ownerSessionID, jobID: job.id, at: now)
            } catch {
                let message = "本地转写未完成：\(String(describing: error))"
                let failed = job.failing(code: .transcriptionFailed, message: message, at: now)
                try store.save(failed)
                try store.appendEvent(MediaTranscriptionJobEvent(jobID: failed.id, state: .failed, message: "Local transcription failed", createdAt: now, metadata: ["diagnostics": message]), sessionID: failed.ownerSessionID)
                throw MediaTranscriptionTaskHandlerError.transcriptUnavailable(message)
            }
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

    private func acquirePlatformSubtitles(for job: BrowserMediaTranscriptionJob, at now: Date) throws -> BrowserMediaTranscriptionJob {
        guard let url = primaryMediaURL(for: job) else { return job }
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let subtitleDirectory = jobDirectory.appendingPathComponent("subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        let ytDLP = store.paths.sidecarsDirectory.appendingPathComponent("yt-dlp/runtime/yt-dlp.sh")
        let outputTemplate = subtitleDirectory.appendingPathComponent("%(id)s.%(ext)s").path
        let result = runProcess(
            executable: ytDLP,
            arguments: ytDLPBaseArguments(jobDirectory: jobDirectory)
                + ["--skip-download", "--write-subs", "--write-auto-subs", "--sub-langs", "all", "--sub-format", "vtt/srt/best", "-o", outputTemplate, url]
        )
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: job.id, state: .acquiringSubtitles, message: "yt-dlp subtitle acquisition exited with \(result.exitCode)", createdAt: now, metadata: ["stderr": String(result.stderr.prefix(2000)), "stdout": String(result.stdout.prefix(2000))]), sessionID: job.ownerSessionID)
        guard result.exitCode == 0 else { return job }
        let subtitleFiles = try FileManager.default.contentsOfDirectory(at: subtitleDirectory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let firstSubtitle = subtitleFiles.first else { return job }
        let subtitleText = (try? String(contentsOf: firstSubtitle, encoding: .utf8)) ?? ""
        let plainText = Self.plainText(fromSubtitleText: subtitleText)
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return job }
        let transcriptMarkdown = Self.transcriptMarkdown(job: job, body: plainText, sourceKind: "platform subtitles")
        let transcriptDirectory = jobDirectory.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        let transcriptURL = transcriptDirectory.appendingPathComponent("transcript.md")
        let transcriptTextURL = transcriptDirectory.appendingPathComponent("transcript.txt")
        try transcriptMarkdown.write(to: transcriptURL, atomically: true, encoding: .utf8)
        try plainText.write(to: transcriptTextURL, atomically: true, encoding: .utf8)
        var next = job
        next.artifacts.subtitles = subtitleFiles.map { artifactRef(kind: "subtitle", fileURL: $0, relativeTo: jobDirectory, at: now) }
        next.artifacts.transcriptMarkdown = artifactRef(kind: "transcriptMarkdown", fileURL: transcriptURL, relativeTo: jobDirectory, at: now)
        next.artifacts.transcriptText = artifactRef(kind: "transcriptText", fileURL: transcriptTextURL, relativeTo: jobDirectory, at: now)
        let attachment = try MediaTranscriptionAttachmentWriter(paths: store.paths).write(job: next, payload: MediaTranscriptionAttachmentPayload(transcriptMarkdown: transcriptMarkdown, transcriptText: plainText, displayName: "media-transcript.md"), now: now)
        next.artifacts.attachmentIDs.append(attachment.attachmentID)
        try store.save(next)
        return next
    }

    private func acquireAudio(for job: BrowserMediaTranscriptionJob, at now: Date) throws -> BrowserMediaTranscriptionJob {
        guard let url = primaryMediaURL(for: job) else { return job }
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let audioDirectory = jobDirectory.appendingPathComponent("audio/original", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let ytDLP = store.paths.sidecarsDirectory.appendingPathComponent("yt-dlp/runtime/yt-dlp.sh")
        let outputTemplate = audioDirectory.appendingPathComponent("%(id)s.%(ext)s").path
        let result = runProcess(executable: ytDLP, arguments: ytDLPBaseArguments(jobDirectory: jobDirectory) + ["-x", "--audio-format", "m4a", "-o", outputTemplate, url])
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: job.id, state: .acquiringAudio, message: "yt-dlp audio acquisition exited with \(result.exitCode)", createdAt: now, metadata: ["stderr": String(result.stderr.prefix(2000)), "stdout": String(result.stdout.prefix(2000))]), sessionID: job.ownerSessionID)
        guard result.exitCode == 0 else { return job }
        let audioFiles = try FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { !["part", "ytdl"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let firstAudio = audioFiles.first else { return job }
        var next = job
        next.artifacts.originalAudio = artifactRef(kind: "originalAudio", fileURL: firstAudio, relativeTo: jobDirectory, at: now)
        try store.save(next)
        return next
    }

    private func normalizeAudio(for job: BrowserMediaTranscriptionJob, at now: Date) throws -> BrowserMediaTranscriptionJob {
        guard let original = job.artifacts.originalAudio else { return job }
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let input = jobDirectory.appendingPathComponent(original.relativePath)
        guard FileManager.default.fileExists(atPath: input.path) else { return job }
        let normalizedDirectory = jobDirectory.appendingPathComponent("audio/normalized", isDirectory: true)
        try FileManager.default.createDirectory(at: normalizedDirectory, withIntermediateDirectories: true)
        let output = normalizedDirectory.appendingPathComponent("normalized.wav")
        let ffmpeg = store.paths.sidecarsDirectory.appendingPathComponent("ffmpeg/runtime/ffmpeg")
        let result = runProcess(executable: ffmpeg, arguments: ["-y", "-i", input.path, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", output.path])
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: job.id, state: .normalizingAudio, message: "ffmpeg normalization exited with \(result.exitCode)", createdAt: now, metadata: ["stderr": String(result.stderr.prefix(2000)), "stdout": String(result.stdout.prefix(2000))]), sessionID: job.ownerSessionID)
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: output.path) else { return job }
        var next = job
        next.artifacts.normalizedAudio = artifactRef(kind: "normalizedAudio", fileURL: output, relativeTo: jobDirectory, at: now)
        try store.save(next)
        return next
    }

    private func runLocalTranscription(for job: BrowserMediaTranscriptionJob, at now: Date) async throws -> BrowserMediaTranscriptionJob {
        guard let normalized = job.artifacts.normalizedAudio else { return job }
        let jobDirectory = store.jobDirectory(sessionID: job.ownerSessionID, jobID: job.id)
        let normalizedAudioURL = jobDirectory.appendingPathComponent(normalized.relativePath)
        guard FileManager.default.fileExists(atPath: normalizedAudioURL.path) else { return job }
        let selectedModel = SharedWhisperKitRuntimeProvider.preferredModel(
            for: speechModelPolicy(for: job.request.qualityProfile),
            runtimeRoot: store.paths.sidecarsDirectory
        )
        let modelDirectory = selectedModel.map {
            store.paths.sidecarsDirectory
                .appendingPathComponent("whisperkit", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
        }
        let result = try await localTranscriber.transcribe(MediaLocalTranscriptionRequest(
            job: job,
            normalizedAudioURL: normalizedAudioURL,
            modelDirectory: modelDirectory,
            qualityProfile: job.request.qualityProfile,
            preferredLanguageCode: job.request.preferredLanguageCode
        ))
        let plainText = result.plainText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !plainText.isEmpty else { throw MediaLocalTranscriptionProviderError.emptyTranscript }
        let transcriptMarkdown = Self.transcriptMarkdown(job: job, body: plainText, sourceKind: "local transcription")
        let transcriptDirectory = jobDirectory.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        let transcriptURL = transcriptDirectory.appendingPathComponent("transcript.md")
        let transcriptTextURL = transcriptDirectory.appendingPathComponent("transcript.txt")
        try transcriptMarkdown.write(to: transcriptURL, atomically: true, encoding: String.Encoding.utf8)
        try plainText.write(to: transcriptTextURL, atomically: true, encoding: String.Encoding.utf8)
        var next = job
        next.artifacts.transcriptMarkdown = artifactRef(kind: "transcriptMarkdown", fileURL: transcriptURL, relativeTo: jobDirectory, at: now)
        next.artifacts.transcriptText = artifactRef(kind: "transcriptText", fileURL: transcriptTextURL, relativeTo: jobDirectory, at: now)
        if let segmentsJSONL = result.segmentsJSONL {
            let segmentsURL = transcriptDirectory.appendingPathComponent("segments.jsonl")
            try segmentsJSONL.write(to: segmentsURL, atomically: true, encoding: String.Encoding.utf8)
            next.artifacts.segmentsJSONL = artifactRef(kind: "segmentsJSONL", fileURL: segmentsURL, relativeTo: jobDirectory, at: now)
        }
        let diagnosticsJSON: String? = result.diagnostics.isEmpty ? nil : String(data: try JSONSerialization.data(withJSONObject: ["entries": result.diagnostics], options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)
        let attachment = try MediaTranscriptionAttachmentWriter(paths: store.paths).write(
            job: next,
            payload: MediaTranscriptionAttachmentPayload(
                transcriptMarkdown: transcriptMarkdown,
                transcriptText: plainText,
                segmentsJSONL: result.segmentsJSONL,
                diagnosticsJSON: diagnosticsJSON,
                displayName: "media-transcript.md"
            ),
            now: now
        )
        next.artifacts.attachmentIDs.append(attachment.attachmentID)
        try store.save(next)
        try store.appendEvent(MediaTranscriptionJobEvent(jobID: next.id, state: .transcribing, message: "Local transcription produced transcript artifacts", createdAt: now, metadata: ["diagnostics": result.diagnostics.joined(separator: "; ")]), sessionID: next.ownerSessionID)
        return next
    }

    private func speechModelPolicy(for qualityProfile: MediaTranscriptionQualityProfile) -> SpeechInputModelPolicy {
        switch qualityProfile {
        case .fast: .speedFirst
        case .balanced: .balanced
        case .highAccuracy: .highAccuracy
        }
    }

    private func primaryMediaURL(for job: BrowserMediaTranscriptionJob) -> String? {
        let candidates = job.source.mediaElements.compactMap(\.sourceURLString)
            + job.source.openGraphMedia.map(\.sourceURLString)
            + [job.source.canonicalURLString, job.source.pageURLString].compactMap { $0 }
        return candidates.first { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        }
    }

    private func ytDLPBaseArguments(jobDirectory: URL) -> [String] {
        let tempDirectory = jobDirectory.appendingPathComponent("tmp", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return [
            "--ffmpeg-location", store.paths.sidecarsDirectory.appendingPathComponent("ffmpeg/runtime").path,
            "--paths", "temp:\(tempDirectory.path)"
        ]
    }

    private func runProcess(executable: URL, arguments: [String]) -> MediaProcessResult {
        processRunner.run(MediaProcessInvocation(executable: executable, arguments: arguments))
    }

    private func artifactRef(kind: String, fileURL: URL, relativeTo root: URL, at now: Date) -> MediaTranscriptionArtifactRef {
        let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return MediaTranscriptionArtifactRef(kind: kind, relativePath: relative, byteCount: size, createdAt: now)
    }

    private static func plainText(fromSubtitleText text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line == "WEBVTT" { return false }
                if line.contains("-->") { return false }
                if Int(line) != nil { return false }
                if line.hasPrefix("NOTE") || line.hasPrefix("STYLE") || line.hasPrefix("REGION") { return false }
                return true
            }
            .joined(separator: "\n")
    }

    private static func transcriptMarkdown(job: BrowserMediaTranscriptionJob, body: String, sourceKind: String) -> String {
        let title = job.source.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? job.source.pageTitle! : "网页媒体转写"
        return """
        # \(title)

        - Source: \(job.source.pageURLString)
        - Transcript source: \(sourceKind)
        - Job ID: \(job.id)

        ## Transcript

        \(body)
        """
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
        let userFacing = diagnostics.joined(separator: "；")
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
