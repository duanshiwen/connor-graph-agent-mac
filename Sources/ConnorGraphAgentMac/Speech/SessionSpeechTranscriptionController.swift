@preconcurrency import AVFoundation
import Foundation
import Speech
import ConnorGraphAppSupport
import ConnorGraphCore
import WhisperKit

private final class WhisperKitSpeechFinalTranscriber: @unchecked Sendable {
    private let sidecarsDirectory: URL
    private let bundledRuntimeDirectory: URL?
    private var cachedModelFolder: String?
    private var cachedWhisperKit: WhisperKit?

    init(sidecarsDirectory: URL, bundledRuntimeDirectory: URL? = MediaRuntimeSupervisor.defaultBundledRuntimeDirectory()) {
        self.sidecarsDirectory = sidecarsDirectory
        self.bundledRuntimeDirectory = bundledRuntimeDirectory
    }

    func transcribe(audioURL: URL, policy: SpeechInputModelPolicy = .automaticRecommended) async throws -> String? {
        let provider = SharedWhisperKitRuntimeProvider(sidecarsDirectory: sidecarsDirectory, bundledRuntimeDirectory: bundledRuntimeDirectory)
        let modelID = await provider.preferredModel(for: policy) ?? WhisperKitModelInventory.defaultModel
        guard let modelFolder = resolveModelFolder(modelID: modelID) else { return nil }
        let modelFolderPath = modelFolder.path
        let pipe: WhisperKit
        if cachedModelFolder == modelFolderPath, let cachedWhisperKit {
            pipe = cachedWhisperKit
        } else {
            cachedWhisperKit = nil
            cachedModelFolder = nil
            pipe = try await WhisperKit(WhisperKitConfig(model: modelID, modelFolder: modelFolderPath, verbose: false, download: false))
            cachedWhisperKit = pipe
            cachedModelFolder = modelFolderPath
        }
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func cancel() {
        // WhisperKit transcribe observes Task cancellation; no extra mutable state is needed here.
    }

    private func resolveModelFolder(modelID: String) -> URL? {
        let candidates = [
            bundledRuntimeDirectory,
            Optional(sidecarsDirectory)
        ].compactMap { $0 }
            .map { $0.appendingPathComponent("whisperkit/models/\(modelID)", isDirectory: true) }
        return candidates.first { WhisperKitModelInventory.isModelUsable($0) }
    }
}

@MainActor
final class SessionSpeechTranscriptionController: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?

    private let localeIdentifier: String?
    private let finalTranscriber: WhisperKitSpeechFinalTranscriber?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionGeneration = UUID()
    private var isStopping = false
    private var latestPartialTranscript: String = ""
    private var onFinalTranscript: (@MainActor @Sendable (String) -> Void)?
    private var finalTranscriptionTask: Task<Void, Never>?

    init(localeIdentifier: String? = "zh-CN", sidecarsDirectory: URL? = nil) {
        self.localeIdentifier = localeIdentifier
        self.finalTranscriber = sidecarsDirectory.map { WhisperKitSpeechFinalTranscriber(sidecarsDirectory: $0) }
    }

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onFinal: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stop(reason: .appLifecycle)
        let generation = UUID()
        recognitionGeneration = generation
        runningSessionID = sessionID
        latestPartialTranscript = ""
        onFinalTranscript = onFinal

        requestMicrophoneAccessIfNeeded { [weak self] microphoneGranted in
            Task { @MainActor in
                guard let self,
                      self.runningSessionID == sessionID,
                      self.recognitionGeneration == generation else { return }
                guard microphoneGranted else {
                    self.cleanupAfterFailure()
                    onError("麦克风权限已被拒绝，请在系统设置中允许康纳同学访问麦克风。")
                    return
                }
                self.requestSpeechRecognitionAccessIfNeeded(
                    sessionID: sessionID,
                    generation: generation,
                    onPartial: onPartial,
                    onFinal: onFinal,
                    onError: onError
                )
            }
        }
    }

    func stop(reason: SessionSpeechTranscriptionStopReason) {
        guard runningSessionID != nil || audioEngine != nil || recognitionRequest != nil || recognitionTask != nil || finalTranscriptionTask != nil else { return }
        isStopping = true
        let finalTranscript = latestPartialTranscript
        let finalCallback = onFinalTranscript
        let audioURL = recordingURL
        let finalTranscriber = finalTranscriber
        recognitionGeneration = UUID()
        runningSessionID = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioFile = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        audioEngine = nil

        finalTranscriptionTask?.cancel()
        finalTranscriptionTask = nil

        if reason == .manual {
            if let audioURL, let finalTranscriber {
                finalTranscriptionTask = Task { [finalTranscript, finalCallback] in
                    do {
                        let whisperText = try await finalTranscriber.transcribe(audioURL: audioURL)
                        try? FileManager.default.removeItem(at: audioURL)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { finalCallback?(whisperText ?? finalTranscript) }
                    } catch {
                        try? FileManager.default.removeItem(at: audioURL)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { finalCallback?(finalTranscript) }
                    }
                }
            } else {
                finalCallback?(finalTranscript)
            }
        } else if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        latestPartialTranscript = ""
        onFinalTranscript = nil
        isStopping = false
    }

    private func requestMicrophoneAccessIfNeeded(completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func requestSpeechRecognitionAccessIfNeeded(
        sessionID: String,
        generation: UUID,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onFinal: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            startAudioCapture(
                sessionID: sessionID,
                generation: generation,
                shouldUseApplePartial: currentStatus == .authorized,
                onPartial: onPartial,
                onError: onError
            )
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            Task { @MainActor in
                self?.startAudioCapture(
                    sessionID: sessionID,
                    generation: generation,
                    shouldUseApplePartial: authorizationStatus == .authorized,
                    onPartial: onPartial,
                    onError: onError
                )
            }
        }
    }

    private func startAudioCapture(
        sessionID: String,
        generation: UUID,
        shouldUseApplePartial: Bool,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        guard runningSessionID == sessionID, recognitionGeneration == generation else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-speech-\(generation.uuidString)")
            .appendingPathExtension("wav")

        do {
            let file = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
            var request: SFSpeechAudioBufferRecognitionRequest?
            if shouldUseApplePartial, let recognizer = makeSpeechRecognizer(), recognizer.isAvailable {
                let speechRequest = SFSpeechAudioBufferRecognitionRequest()
                speechRequest.shouldReportPartialResults = true
                speechRequest.taskHint = .dictation
                request = speechRequest
                self.recognitionRequest = speechRequest
                self.speechRecognizer = recognizer
                recognitionTask = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self,
                              self.runningSessionID == sessionID,
                              self.recognitionGeneration == generation else { return }
                        if let result {
                            let transcript = result.bestTranscription.formattedString
                            self.latestPartialTranscript = transcript
                            onPartial(transcript)
                        }
                        if let error, !self.isStopping {
                            // Keep recording for WhisperKit final even if Apple partial fails.
                            self.latestPartialTranscript = self.latestPartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                            if self.latestPartialTranscript.isEmpty {
                                onPartial("")
                            }
                            print("Apple Speech partial failed: \(error.localizedDescription)")
                        }
                    }
                }
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                request?.append(buffer)
                do {
                    try file.write(from: buffer)
                } catch {
                    // Keep the audio tap alive; final pass will fall back to latest partial if the file is unusable.
                }
            }

            self.audioEngine = engine
            self.audioFile = file
            self.recordingURL = recordingURL
            isStopping = false
            try engine.start()
        } catch {
            cleanupAfterFailure()
            onError(error.localizedDescription)
        }
    }

    private func makeSpeechRecognizer() -> SFSpeechRecognizer? {
        guard let localeIdentifier else {
            return SFSpeechRecognizer()
        }

        let locale = Locale(identifier: localeIdentifier)
        if SFSpeechRecognizer.supportedLocales().contains(locale) {
            return SFSpeechRecognizer(locale: locale)
        }

        return SFSpeechRecognizer()
    }

    private func cleanupAfterFailure() {
        stop(reason: .appLifecycle)
    }
}
