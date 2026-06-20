import Foundation
import Testing
@testable import ConnorGraphCore

@Suite("Browser Media Transcription Domain Tests")
struct BrowserMediaTranscriptionDomainTests {
    @Test func jobStateMachineAllowsProductionPathAndTerminalGuards() throws {
        var job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", mediaElements: [BrowserDetectedMediaElement(id: "video-0", kind: "video")]),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        for state in [
            MediaTranscriptionJobState.preparingRuntime,
            .probingMedia,
            .acquiringSubtitles,
            .acquiringAudio,
            .normalizingAudio,
            .transcribing,
            .diarizing,
            .postProcessing,
            .writingAttachments,
            .sendingToSession,
            .completed
        ] {
            job = try job.transitioning(to: state, at: Date(timeIntervalSince1970: 10))
            #expect(job.state == state)
            #expect(job.progress.state == state)
        }

        #expect(job.completedAt == Date(timeIntervalSince1970: 10))
        #expect(throws: BrowserMediaTranscriptionErrorCode.self) {
            _ = try job.transitioning(to: .queued)
        }
    }

    @Test func jobSupportsSubtitleOnlyPathAndRetryFromFailure() throws {
        var job = BrowserMediaTranscriptionJob(
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/audio")
        )

        job = try job.transitioning(to: .preparingRuntime)
        job = try job.transitioning(to: .probingMedia)
        job = try job.transitioning(to: .acquiringSubtitles)
        job = try job.transitioning(to: .postProcessing)
        job = try job.transitioning(to: .writingAttachments)
        job = try job.transitioning(to: .sendingToSession)
        job = try job.transitioning(to: .completed)

        var failed = BrowserMediaTranscriptionJob(ownerSessionID: "session-1", source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com"))
            .failing(code: .mediaProbeFailed, message: "no extractor")
        #expect(failed.state == .failed)
        #expect(failed.lastErrorCode == .mediaProbeFailed)
        failed = try failed.transitioning(to: .queued)
        #expect(failed.state == .queued)
        #expect(failed.lastErrorCode == nil)
    }

    @Test func sourceSnapshotAndJobRoundTripThroughCodable() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let job = BrowserMediaTranscriptionJob(
            id: "job-42",
            ownerSessionID: "session-42",
            source: BrowserMediaSourceSnapshot(
                pageURLString: "https://example.com/watch?v=42",
                pageTitle: "Example Video",
                detectedAt: now,
                mediaElements: [BrowserDetectedMediaElement(id: "video-0", kind: "video", sourceURLString: "https://cdn.example.com/video.mp4", durationSeconds: 120, isPaused: false)],
                openGraphMedia: [BrowserDetectedMediaCandidate(id: "og-0", sourceURLString: "https://example.com/og.mp4", type: "video/mp4")],
                canonicalURLString: "https://example.com/watch/42"
            ),
            request: MediaTranscriptionRequest(preferredLanguageCode: "zh", shouldRunSpeakerDiarization: true, qualityProfile: .highAccuracy),
            state: .queued,
            progress: MediaTranscriptionProgress(state: .queued, fractionCompleted: 0.25, currentStepDescription: "Preparing", updatedAt: now),
            runtime: MediaRuntimeSnapshot(
                python: MediaRuntimeComponentSnapshot(id: "python", version: "3.12", source: "bundled", checksum: "abc", isAvailable: true),
                ytDLP: MediaRuntimeComponentSnapshot(id: "yt-dlp", version: "2026.06", source: "vendored", isAvailable: true),
                ffmpeg: MediaRuntimeComponentSnapshot(id: "ffmpeg", version: "7", source: "bundled", isAvailable: true),
                whisperKit: MediaRuntimeComponentSnapshot(id: "whisperkit", version: "0.12", source: "spm", isAvailable: true),
                capturedAt: now
            ),
            artifacts: MediaTranscriptionArtifacts(transcriptMarkdown: MediaTranscriptionArtifactRef(kind: "transcript.md", relativePath: "data/media-jobs/job-42/transcript.md", createdAt: now)),
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BrowserMediaTranscriptionJob.self, from: data)

        #expect(decoded == job)
        #expect(decoded.source.hasDetectedMedia)
        #expect(decoded.recoveryPolicy == .restoreIfQueuedOrRunning)
    }
}
