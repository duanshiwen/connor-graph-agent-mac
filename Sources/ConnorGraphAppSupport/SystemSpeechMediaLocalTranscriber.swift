import Foundation
@preconcurrency import Speech
import ConnorGraphCore

public struct SystemSpeechMediaLocalTranscriber: MediaLocalTranscriptionProviding, Sendable {
    public init() {}

    public func transcribe(_ request: MediaLocalTranscriptionRequest) async throws -> MediaLocalTranscriptionResult {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            throw MediaLocalTranscriptionProviderError.unavailable("macOS Speech recognition is not authorized: \(authorizationDescription(status))")
        }
        guard FileManager.default.fileExists(atPath: request.normalizedAudioURL.path) else {
            throw MediaLocalTranscriptionProviderError.unavailable("Normalized audio file is missing: \(request.normalizedAudioURL.path)")
        }
        let locale = request.preferredLanguageCode.flatMap(Locale.init(identifier:))
        let recognizer: SFSpeechRecognizer?
        if let locale, SFSpeechRecognizer.supportedLocales().contains(locale) {
            recognizer = SFSpeechRecognizer(locale: locale)
        } else {
            recognizer = SFSpeechRecognizer()
        }
        guard let recognizer, recognizer.isAvailable else {
            throw MediaLocalTranscriptionProviderError.unavailable("macOS Speech recognizer is not available")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let state = SpeechRecognitionContinuationState(continuation: continuation)
            let recognitionRequest = SFSpeechURLRecognitionRequest(url: request.normalizedAudioURL)
            recognitionRequest.shouldReportPartialResults = false
            if #available(macOS 13.0, *) {
                recognitionRequest.addsPunctuation = true
            }
            if #available(macOS 13.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = false
            }
            _ = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let error {
                    state.resume(throwing: MediaLocalTranscriptionProviderError.unavailable("macOS Speech recognition failed: \(error.localizedDescription)"))
                    return
                }
                guard let result else { return }
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if result.isFinal {
                    guard !text.isEmpty else {
                        state.resume(throwing: MediaLocalTranscriptionProviderError.emptyTranscript)
                        return
                    }
                    let segments = result.bestTranscription.segments.map { segment in
                        [
                            "text": segment.substring,
                            "timestamp": segment.timestamp,
                            "duration": segment.duration,
                            "confidence": segment.confidence
                        ] as [String: Any]
                    }
                    let segmentsJSONL = segments.compactMap { segment -> String? in
                        guard let data = try? JSONSerialization.data(withJSONObject: segment, options: [.sortedKeys]) else { return nil }
                        return String(data: data, encoding: .utf8)
                    }.joined(separator: "\n")
                    state.resume(returning: MediaLocalTranscriptionResult(
                        plainText: text,
                        segmentsJSONL: segmentsJSONL.isEmpty ? nil : segmentsJSONL + "\n",
                        diagnostics: ["macOS Speech local file recognition completed"]
                    ))
                }
            }
        }
    }

    private func authorizationDescription(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}

private final class SpeechRecognitionContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<MediaLocalTranscriptionResult, Error>

    init(continuation: CheckedContinuation<MediaLocalTranscriptionResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: MediaLocalTranscriptionResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
    }
}
