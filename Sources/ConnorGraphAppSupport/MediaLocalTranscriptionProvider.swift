import Foundation
import ConnorGraphCore

public struct MediaLocalTranscriptionRequest: Sendable, Equatable {
    public var job: BrowserMediaTranscriptionJob
    public var normalizedAudioURL: URL
    public var modelDirectory: URL?
    public var qualityProfile: MediaTranscriptionQualityProfile
    public var preferredLanguageCode: String?

    public init(
        job: BrowserMediaTranscriptionJob,
        normalizedAudioURL: URL,
        modelDirectory: URL? = nil,
        qualityProfile: MediaTranscriptionQualityProfile,
        preferredLanguageCode: String? = nil
    ) {
        self.job = job
        self.normalizedAudioURL = normalizedAudioURL
        self.modelDirectory = modelDirectory
        self.qualityProfile = qualityProfile
        self.preferredLanguageCode = preferredLanguageCode
    }
}

public struct MediaLocalTranscriptionResult: Sendable, Equatable {
    public var plainText: String
    public var segmentsJSONL: String?
    public var diagnostics: [String]

    public init(plainText: String, segmentsJSONL: String? = nil, diagnostics: [String] = []) {
        self.plainText = plainText
        self.segmentsJSONL = segmentsJSONL
        self.diagnostics = diagnostics
    }
}

public protocol MediaLocalTranscriptionProviding: Sendable {
    func transcribe(_ request: MediaLocalTranscriptionRequest) async throws -> MediaLocalTranscriptionResult
}

public enum MediaLocalTranscriptionProviderError: Error, Sendable, Equatable, CustomStringConvertible {
    case unavailable(String)
    case emptyTranscript

    public var description: String {
        switch self {
        case .unavailable(let reason): "localTranscriberUnavailable: \(reason)"
        case .emptyTranscript: "localTranscriberEmptyTranscript"
        }
    }
}

public struct UnavailableMediaLocalTranscriber: MediaLocalTranscriptionProviding, Sendable {
    public var reason: String

    public init(reason: String = "Local WhisperKit transcription provider is not wired yet") {
        self.reason = reason
    }

    public func transcribe(_ request: MediaLocalTranscriptionRequest) async throws -> MediaLocalTranscriptionResult {
        throw MediaLocalTranscriptionProviderError.unavailable(reason)
    }
}
