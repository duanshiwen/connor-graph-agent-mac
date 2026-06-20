import Foundation

public enum BrowserMediaTranscriptionErrorCode: String, Codable, Sendable, Equatable, CaseIterable, Error {
    case invalidTransition
    case runtimeUnavailable
    case mediaProbeFailed
    case subtitleAcquisitionFailed
    case audioAcquisitionFailed
    case audioNormalizationFailed
    case transcriptionFailed
    case diarizationFailed
    case attachmentWriteFailed
    case sessionReturnFailed
    case cancelled
}

public enum MediaTranscriptionJobState: String, Codable, Sendable, Equatable, CaseIterable {
    case queued
    case preparingRuntime
    case probingMedia
    case acquiringSubtitles
    case acquiringAudio
    case normalizingAudio
    case transcribing
    case diarizing
    case postProcessing
    case writingAttachments
    case sendingToSession
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }

    public func canTransition(to next: MediaTranscriptionJobState) -> Bool {
        guard self != next else { return true }
        if next == .cancelled { return !isTerminal }
        if next == .failed { return !isTerminal }
        switch (self, next) {
        case (.queued, .preparingRuntime),
             (.preparingRuntime, .probingMedia),
             (.probingMedia, .acquiringSubtitles),
             (.probingMedia, .acquiringAudio),
             (.acquiringSubtitles, .acquiringAudio),
             (.acquiringSubtitles, .postProcessing),
             (.acquiringAudio, .normalizingAudio),
             (.normalizingAudio, .transcribing),
             (.transcribing, .diarizing),
             (.transcribing, .postProcessing),
             (.diarizing, .postProcessing),
             (.postProcessing, .writingAttachments),
             (.writingAttachments, .sendingToSession),
             (.sendingToSession, .completed),
             (.failed, .queued):
            return true
        default:
            return false
        }
    }
}

public enum MediaTranscriptionOutputPurpose: String, Codable, Sendable, Equatable, CaseIterable {
    case summary
    case knowledgeExtraction
    case discussion
    case knowledgeBaseCandidate
}

public enum MediaTranscriptionQualityProfile: String, Codable, Sendable, Equatable, CaseIterable {
    case fast
    case balanced
    case highAccuracy
}

public enum BrowserMediaTranscriptionMode: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case transcribeOnly
    case transcribeAndSummarize
    case transcribeSummarizeAndChapters

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .transcribeOnly: "只转写"
        case .transcribeAndSummarize: "转写并提炼"
        case .transcribeSummarizeAndChapters: "转写 + 提炼 + 章节"
        }
    }
}

public enum BrowserMediaTranscriptionSourceKind: String, Codable, Sendable, Equatable {
    case mediaElement
    case openGraph
}

public struct BrowserMediaTranscriptionSourceOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: BrowserMediaTranscriptionSourceKind
    public var mediaKind: String
    public var title: String
    public var sourceURLString: String?
    public var durationSeconds: TimeInterval?
    public var isPaused: Bool?
    public var isMuted: Bool?
    public var readyState: Int?

    public init(
        id: String,
        kind: BrowserMediaTranscriptionSourceKind,
        mediaKind: String,
        title: String,
        sourceURLString: String? = nil,
        durationSeconds: TimeInterval? = nil,
        isPaused: Bool? = nil,
        isMuted: Bool? = nil,
        readyState: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.mediaKind = mediaKind
        self.title = title
        self.sourceURLString = sourceURLString
        self.durationSeconds = durationSeconds
        self.isPaused = isPaused
        self.isMuted = isMuted
        self.readyState = readyState
    }
}

public struct BrowserMediaTranscriptionOptions: Codable, Sendable, Equatable {
    public var shouldPreferPlatformSubtitles: Bool
    public var shouldDownloadAudio: Bool
    public var shouldRunLocalTranscription: Bool
    public var shouldRunSpeakerDiarization: Bool
    public var shouldGenerateChapters: Bool
    public var shouldGenerateSummary: Bool

    public init(
        shouldPreferPlatformSubtitles: Bool = true,
        shouldDownloadAudio: Bool = true,
        shouldRunLocalTranscription: Bool = true,
        shouldRunSpeakerDiarization: Bool = false,
        shouldGenerateChapters: Bool = true,
        shouldGenerateSummary: Bool = true
    ) {
        self.shouldPreferPlatformSubtitles = shouldPreferPlatformSubtitles
        self.shouldDownloadAudio = shouldDownloadAudio
        self.shouldRunLocalTranscription = shouldRunLocalTranscription
        self.shouldRunSpeakerDiarization = shouldRunSpeakerDiarization
        self.shouldGenerateChapters = shouldGenerateChapters
        self.shouldGenerateSummary = shouldGenerateSummary
    }

    public static func defaults(for mode: BrowserMediaTranscriptionMode) -> BrowserMediaTranscriptionOptions {
        switch mode {
        case .transcribeOnly:
            BrowserMediaTranscriptionOptions(shouldGenerateChapters: false, shouldGenerateSummary: false)
        case .transcribeAndSummarize:
            BrowserMediaTranscriptionOptions(shouldGenerateChapters: false, shouldGenerateSummary: true)
        case .transcribeSummarizeAndChapters:
            BrowserMediaTranscriptionOptions(shouldGenerateChapters: true, shouldGenerateSummary: true)
        }
    }

    public func mediaTranscriptionRequest(qualityProfile: MediaTranscriptionQualityProfile = .balanced) -> MediaTranscriptionRequest {
        MediaTranscriptionRequest(
            shouldPreferPlatformSubtitles: shouldPreferPlatformSubtitles,
            shouldDownloadAudio: shouldDownloadAudio,
            shouldRunLocalTranscription: shouldRunLocalTranscription,
            shouldRunSpeakerDiarization: shouldRunSpeakerDiarization,
            shouldGenerateChapters: shouldGenerateChapters,
            qualityProfile: qualityProfile,
            outputPurpose: shouldGenerateSummary ? .summary : .discussion
        )
    }
}

public struct BrowserMediaTranscriptionSelection: Codable, Sendable, Equatable {
    public var snapshot: BrowserMediaSourceSnapshot
    public var selectedSourceIDs: [String]
    public var mode: BrowserMediaTranscriptionMode
    public var options: BrowserMediaTranscriptionOptions

    public init(
        snapshot: BrowserMediaSourceSnapshot,
        selectedSourceIDs: [String],
        mode: BrowserMediaTranscriptionMode = .transcribeSummarizeAndChapters,
        options: BrowserMediaTranscriptionOptions? = nil
    ) {
        self.snapshot = snapshot
        self.selectedSourceIDs = selectedSourceIDs
        self.mode = mode
        self.options = options ?? BrowserMediaTranscriptionOptions.defaults(for: mode)
    }

    public static func defaultAllSources(from snapshot: BrowserMediaSourceSnapshot, mode: BrowserMediaTranscriptionMode = .transcribeSummarizeAndChapters) -> BrowserMediaTranscriptionSelection {
        BrowserMediaTranscriptionSelection(
            snapshot: snapshot,
            selectedSourceIDs: snapshot.transcriptionSourceOptions.map(\.id),
            mode: mode
        )
    }

    public var selectedSnapshot: BrowserMediaSourceSnapshot {
        guard !selectedSourceIDs.isEmpty else { return snapshot }
        let selected = Set(selectedSourceIDs)
        var copy = snapshot
        copy.mediaElements = snapshot.mediaElements.filter { selected.contains(BrowserMediaSourceSnapshot.transcriptionSourceID(forMediaElement: $0)) }
        copy.openGraphMedia = snapshot.openGraphMedia.filter { selected.contains(BrowserMediaSourceSnapshot.transcriptionSourceID(forOpenGraphMedia: $0)) }
        return copy
    }

    public var selectedSingleSourceSnapshots: [BrowserMediaSourceSnapshot] {
        let selected = selectedSourceIDs.isEmpty ? Set(snapshot.transcriptionSourceOptions.map(\.id)) : Set(selectedSourceIDs)
        var snapshots: [BrowserMediaSourceSnapshot] = []
        for element in snapshot.mediaElements where selected.contains(BrowserMediaSourceSnapshot.transcriptionSourceID(forMediaElement: element)) {
            var copy = snapshot
            copy.mediaElements = [element]
            copy.openGraphMedia = []
            snapshots.append(copy)
        }
        for candidate in snapshot.openGraphMedia where selected.contains(BrowserMediaSourceSnapshot.transcriptionSourceID(forOpenGraphMedia: candidate)) {
            var copy = snapshot
            copy.mediaElements = []
            copy.openGraphMedia = [candidate]
            snapshots.append(copy)
        }
        return snapshots.isEmpty ? [selectedSnapshot] : snapshots
    }

    public var mediaTranscriptionRequest: MediaTranscriptionRequest {
        options.mediaTranscriptionRequest()
    }
}

public struct BrowserDetectedMediaElement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var sourceURLString: String?
    public var durationSeconds: TimeInterval?
    public var isPaused: Bool
    public var isMuted: Bool
    public var readyState: Int?

    public init(
        id: String,
        kind: String,
        sourceURLString: String? = nil,
        durationSeconds: TimeInterval? = nil,
        isPaused: Bool = true,
        isMuted: Bool = false,
        readyState: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceURLString = sourceURLString
        self.durationSeconds = durationSeconds
        self.isPaused = isPaused
        self.isMuted = isMuted
        self.readyState = readyState
    }
}

public struct BrowserDetectedMediaCandidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceURLString: String
    public var type: String?

    public init(id: String, sourceURLString: String, type: String? = nil) {
        self.id = id
        self.sourceURLString = sourceURLString
        self.type = type
    }
}

public struct BrowserMediaSourceSnapshot: Codable, Sendable, Equatable {
    public var pageURLString: String
    public var pageTitle: String?
    public var detectedAt: Date
    public var mediaElements: [BrowserDetectedMediaElement]
    public var openGraphMedia: [BrowserDetectedMediaCandidate]
    public var canonicalURLString: String?
    public var userVisibleSelection: String?

    public init(
        pageURLString: String,
        pageTitle: String? = nil,
        detectedAt: Date = Date(),
        mediaElements: [BrowserDetectedMediaElement] = [],
        openGraphMedia: [BrowserDetectedMediaCandidate] = [],
        canonicalURLString: String? = nil,
        userVisibleSelection: String? = nil
    ) {
        self.pageURLString = pageURLString
        self.pageTitle = pageTitle
        self.detectedAt = detectedAt
        self.mediaElements = mediaElements
        self.openGraphMedia = openGraphMedia
        self.canonicalURLString = canonicalURLString
        self.userVisibleSelection = userVisibleSelection
    }

    public var hasDetectedMedia: Bool { !mediaElements.isEmpty || !openGraphMedia.isEmpty }

    public var transcriptionSourceOptions: [BrowserMediaTranscriptionSourceOption] {
        let elementOptions = mediaElements.enumerated().map { index, element in
            BrowserMediaTranscriptionSourceOption(
                id: Self.transcriptionSourceID(forMediaElement: element),
                kind: .mediaElement,
                mediaKind: element.kind,
                title: Self.mediaElementTitle(element, index: index),
                sourceURLString: element.sourceURLString,
                durationSeconds: element.durationSeconds,
                isPaused: element.isPaused,
                isMuted: element.isMuted,
                readyState: element.readyState
            )
        }
        let openGraphOptions = openGraphMedia.enumerated().map { index, candidate in
            BrowserMediaTranscriptionSourceOption(
                id: Self.transcriptionSourceID(forOpenGraphMedia: candidate),
                kind: .openGraph,
                mediaKind: candidate.type ?? "metadata",
                title: Self.openGraphTitle(candidate, index: index),
                sourceURLString: candidate.sourceURLString
            )
        }
        return elementOptions + openGraphOptions
    }

    public static func transcriptionSourceID(forMediaElement element: BrowserDetectedMediaElement) -> String {
        "media-element:\(element.id)"
    }

    public static func transcriptionSourceID(forOpenGraphMedia candidate: BrowserDetectedMediaCandidate) -> String {
        "open-graph:\(candidate.id)"
    }

    private static func mediaElementTitle(_ element: BrowserDetectedMediaElement, index: Int) -> String {
        let kind = element.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.isEmpty { return "网页媒体 #\(index + 1)" }
        return "\(kind.capitalized) #\(index + 1)"
    }

    private static func openGraphTitle(_ candidate: BrowserDetectedMediaCandidate, index: Int) -> String {
        if let type = candidate.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
            return "Metadata \(type) #\(index + 1)"
        }
        return "Open Graph 媒体 #\(index + 1)"
    }
}

public struct MediaTranscriptionRequest: Codable, Sendable, Equatable {
    public var preferredLanguageCode: String?
    public var shouldPreferPlatformSubtitles: Bool
    public var shouldDownloadAudio: Bool
    public var shouldRunLocalTranscription: Bool
    public var shouldRunSpeakerDiarization: Bool
    public var shouldGenerateChapters: Bool
    public var qualityProfile: MediaTranscriptionQualityProfile
    public var outputPurpose: MediaTranscriptionOutputPurpose

    public init(
        preferredLanguageCode: String? = nil,
        shouldPreferPlatformSubtitles: Bool = true,
        shouldDownloadAudio: Bool = true,
        shouldRunLocalTranscription: Bool = true,
        shouldRunSpeakerDiarization: Bool = false,
        shouldGenerateChapters: Bool = true,
        qualityProfile: MediaTranscriptionQualityProfile = .balanced,
        outputPurpose: MediaTranscriptionOutputPurpose = .knowledgeExtraction
    ) {
        self.preferredLanguageCode = preferredLanguageCode
        self.shouldPreferPlatformSubtitles = shouldPreferPlatformSubtitles
        self.shouldDownloadAudio = shouldDownloadAudio
        self.shouldRunLocalTranscription = shouldRunLocalTranscription
        self.shouldRunSpeakerDiarization = shouldRunSpeakerDiarization
        self.shouldGenerateChapters = shouldGenerateChapters
        self.qualityProfile = qualityProfile
        self.outputPurpose = outputPurpose
    }
}

public struct MediaRuntimeComponentSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var version: String
    public var source: String
    public var checksum: String?
    public var isAvailable: Bool
    public var diagnostics: String?

    public init(id: String, version: String = "unknown", source: String = "unresolved", checksum: String? = nil, isAvailable: Bool = false, diagnostics: String? = nil) {
        self.id = id
        self.version = version
        self.source = source
        self.checksum = checksum
        self.isAvailable = isAvailable
        self.diagnostics = diagnostics
    }
}

public struct MediaRuntimeSnapshot: Codable, Sendable, Equatable {
    public var python: MediaRuntimeComponentSnapshot
    public var ytDLP: MediaRuntimeComponentSnapshot
    public var ffmpeg: MediaRuntimeComponentSnapshot
    public var whisperKit: MediaRuntimeComponentSnapshot
    public var speakerKit: MediaRuntimeComponentSnapshot?
    public var capturedAt: Date

    public init(
        python: MediaRuntimeComponentSnapshot = MediaRuntimeComponentSnapshot(id: "python"),
        ytDLP: MediaRuntimeComponentSnapshot = MediaRuntimeComponentSnapshot(id: "yt-dlp"),
        ffmpeg: MediaRuntimeComponentSnapshot = MediaRuntimeComponentSnapshot(id: "ffmpeg"),
        whisperKit: MediaRuntimeComponentSnapshot = MediaRuntimeComponentSnapshot(id: "whisperkit"),
        speakerKit: MediaRuntimeComponentSnapshot? = nil,
        capturedAt: Date = Date()
    ) {
        self.python = python
        self.ytDLP = ytDLP
        self.ffmpeg = ffmpeg
        self.whisperKit = whisperKit
        self.speakerKit = speakerKit
        self.capturedAt = capturedAt
    }
}

public struct MediaTranscriptionArtifactRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var relativePath: String
    public var byteCount: Int64?
    public var sha256: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, kind: String, relativePath: String, byteCount: Int64? = nil, sha256: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

public struct MediaTranscriptionArtifacts: Codable, Sendable, Equatable {
    public var metadata: MediaTranscriptionArtifactRef?
    public var subtitles: [MediaTranscriptionArtifactRef]
    public var originalAudio: MediaTranscriptionArtifactRef?
    public var normalizedAudio: MediaTranscriptionArtifactRef?
    public var transcriptMarkdown: MediaTranscriptionArtifactRef?
    public var transcriptText: MediaTranscriptionArtifactRef?
    public var segmentsJSONL: MediaTranscriptionArtifactRef?
    public var vtt: MediaTranscriptionArtifactRef?
    public var chaptersJSON: MediaTranscriptionArtifactRef?
    public var diagnosticsJSON: MediaTranscriptionArtifactRef?
    public var attachmentIDs: [String]

    public init(
        metadata: MediaTranscriptionArtifactRef? = nil,
        subtitles: [MediaTranscriptionArtifactRef] = [],
        originalAudio: MediaTranscriptionArtifactRef? = nil,
        normalizedAudio: MediaTranscriptionArtifactRef? = nil,
        transcriptMarkdown: MediaTranscriptionArtifactRef? = nil,
        transcriptText: MediaTranscriptionArtifactRef? = nil,
        segmentsJSONL: MediaTranscriptionArtifactRef? = nil,
        vtt: MediaTranscriptionArtifactRef? = nil,
        chaptersJSON: MediaTranscriptionArtifactRef? = nil,
        diagnosticsJSON: MediaTranscriptionArtifactRef? = nil,
        attachmentIDs: [String] = []
    ) {
        self.metadata = metadata
        self.subtitles = subtitles
        self.originalAudio = originalAudio
        self.normalizedAudio = normalizedAudio
        self.transcriptMarkdown = transcriptMarkdown
        self.transcriptText = transcriptText
        self.segmentsJSONL = segmentsJSONL
        self.vtt = vtt
        self.chaptersJSON = chaptersJSON
        self.diagnosticsJSON = diagnosticsJSON
        self.attachmentIDs = attachmentIDs
    }
}

public struct MediaTranscriptionProgress: Codable, Sendable, Equatable {
    public var state: MediaTranscriptionJobState
    public var fractionCompleted: Double
    public var currentStepDescription: String
    public var bytesReceived: Int64?
    public var totalBytesExpected: Int64?
    public var updatedAt: Date

    public init(
        state: MediaTranscriptionJobState = .queued,
        fractionCompleted: Double = 0,
        currentStepDescription: String = "Queued",
        bytesReceived: Int64? = nil,
        totalBytesExpected: Int64? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.currentStepDescription = currentStepDescription
        self.bytesReceived = bytesReceived
        self.totalBytesExpected = totalBytesExpected
        self.updatedAt = updatedAt
    }
}

public struct BrowserMediaTranscriptionJob: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerSessionID: String
    public var source: BrowserMediaSourceSnapshot
    public var request: MediaTranscriptionRequest
    public var state: MediaTranscriptionJobState
    public var progress: MediaTranscriptionProgress
    public var runtime: MediaRuntimeSnapshot
    public var artifacts: MediaTranscriptionArtifacts
    public var recoveryPolicy: ConnorTaskRecoveryPolicy
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var lastErrorCode: BrowserMediaTranscriptionErrorCode?
    public var lastErrorMessage: String?

    public init(
        id: String = UUID().uuidString,
        ownerSessionID: String,
        source: BrowserMediaSourceSnapshot,
        request: MediaTranscriptionRequest = MediaTranscriptionRequest(),
        state: MediaTranscriptionJobState = .queued,
        progress: MediaTranscriptionProgress = MediaTranscriptionProgress(),
        runtime: MediaRuntimeSnapshot = MediaRuntimeSnapshot(),
        artifacts: MediaTranscriptionArtifacts = MediaTranscriptionArtifacts(),
        recoveryPolicy: ConnorTaskRecoveryPolicy = .restoreIfQueuedOrRunning,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        lastErrorCode: BrowserMediaTranscriptionErrorCode? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.ownerSessionID = ownerSessionID
        self.source = source
        self.request = request
        self.state = state
        self.progress = progress
        self.runtime = runtime
        self.artifacts = artifacts
        self.recoveryPolicy = recoveryPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
    }

    public func transitioning(to next: MediaTranscriptionJobState, at date: Date = Date()) throws -> BrowserMediaTranscriptionJob {
        guard state.canTransition(to: next) else { throw BrowserMediaTranscriptionErrorCode.invalidTransition }
        var copy = self
        copy.state = next
        copy.updatedAt = date
        copy.progress.state = next
        copy.progress.updatedAt = date
        if next == .completed || next == .cancelled { copy.completedAt = date }
        if next != .failed {
            copy.lastErrorCode = nil
            copy.lastErrorMessage = nil
        }
        return copy
    }

    public func failing(code: BrowserMediaTranscriptionErrorCode, message: String, at date: Date = Date()) -> BrowserMediaTranscriptionJob {
        var copy = self
        copy.state = .failed
        copy.progress.state = .failed
        copy.progress.updatedAt = date
        copy.updatedAt = date
        copy.completedAt = date
        copy.lastErrorCode = code
        copy.lastErrorMessage = message
        return copy
    }
}
