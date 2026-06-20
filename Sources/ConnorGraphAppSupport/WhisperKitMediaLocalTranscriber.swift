import Foundation
import WhisperKit

public struct WhisperKitMediaLocalTranscriber: MediaLocalTranscriptionProviding, Sendable {
    public init() {}

    public func transcribe(_ request: MediaLocalTranscriptionRequest) async throws -> MediaLocalTranscriptionResult {
        guard let modelDirectory = request.modelDirectory else {
            throw MediaLocalTranscriptionProviderError.unavailable("WhisperKit model directory is not selected")
        }
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw MediaLocalTranscriptionProviderError.unavailable("WhisperKit model directory is missing: \(modelDirectory.path)")
        }
        guard FileManager.default.fileExists(atPath: request.normalizedAudioURL.path) else {
            throw MediaLocalTranscriptionProviderError.unavailable("Normalized audio file is missing: \(request.normalizedAudioURL.path)")
        }

        let whisperKit = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelDirectory.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        ))
        let results = try await whisperKit.transcribe(audioPath: request.normalizedAudioURL.path)
        let plainText = results.map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { throw MediaLocalTranscriptionProviderError.emptyTranscript }

        let allSegments = results.flatMap(\.segments)
        let segmentsJSONL = try Self.segmentsJSONL(from: allSegments)
        let languages = Array(Set(results.map(\.language))).sorted()
        let diagnostics = [
            "WhisperKit local transcription completed",
            "modelDirectory=\(modelDirectory.path)",
            "resultCount=\(results.count)",
            "segmentCount=\(allSegments.count)",
            "language=\(languages.joined(separator: ","))"
        ]
        return MediaLocalTranscriptionResult(
            plainText: plainText,
            segmentsJSONL: segmentsJSONL,
            diagnostics: diagnostics
        )
    }

    private static func segmentsJSONL(from segments: [TranscriptionSegment]) throws -> String? {
        guard !segments.isEmpty else { return nil }
        return try segments.map { segment in
            let object: [String: Any] = [
                "id": segment.id,
                "seek": segment.seek,
                "start": Double(segment.start),
                "end": Double(segment.end),
                "duration": Double(segment.duration),
                "text": segment.text,
                "avgLogprob": Double(segment.avgLogprob),
                "compressionRatio": Double(segment.compressionRatio),
                "noSpeechProb": Double(segment.noSpeechProb),
                "temperature": Double(segment.temperature)
            ]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n") + "\n"
    }
}
