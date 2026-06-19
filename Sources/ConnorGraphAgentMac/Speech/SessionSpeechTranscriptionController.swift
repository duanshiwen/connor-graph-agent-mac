import AVFoundation
import Foundation
import Speech

@MainActor
final class SessionSpeechTranscriptionController: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?

    private let localeIdentifier: String?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var didInstallInputTap = false
    private var isStopping = false

    init(localeIdentifier: String? = nil) {
        self.localeIdentifier = localeIdentifier
    }

    func start(
        sessionID: String,
        onPartial: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop(reason: .appLifecycle)
        runningSessionID = sessionID

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            Task { @MainActor in
                guard let self, self.runningSessionID == sessionID else { return }
                guard authorizationStatus == .authorized else {
                    self.cleanupAfterFailure()
                    onError(self.authorizationMessage(for: authorizationStatus))
                    return
                }
                self.startAuthorizedRecognition(sessionID: sessionID, onPartial: onPartial, onError: onError)
            }
        }
    }

    func stop(reason: SessionSpeechTranscriptionStopReason) {
        guard runningSessionID != nil || audioEngine != nil || recognitionRequest != nil || recognitionTask != nil else { return }
        isStopping = true
        runningSessionID = nil

        if let audioEngine {
            audioEngine.stop()
            if didInstallInputTap {
                audioEngine.inputNode.removeTap(onBus: 0)
            }
        }

        // For an ordinary user stop, finish the recognition stream instead of
        // cancelling the task. Cancelling tears down Speech.framework's XPC
        // connection aggressively and can emit noisy runtime diagnostics such as
        // "XPC connection was invalidated" / task-name-port failures even though
        // the app state is healthy. Interruptions still cancel immediately.
        recognitionRequest?.endAudio()
        switch reason {
        case .manual:
            recognitionTask?.finish()
        case .leavingSession, .deletedSession, .appLifecycle:
            recognitionTask?.cancel()
        }

        cleanup()
    }

    private func startAuthorizedRecognition(
        sessionID: String,
        onPartial: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let recognizer: SFSpeechRecognizer?
        if let localeIdentifier {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        } else {
            recognizer = SFSpeechRecognizer()
        }

        guard let recognizer, recognizer.isAvailable else {
            cleanupAfterFailure()
            onError("语音识别当前不可用，请稍后再试。")
            return
        }

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            // Keep live dictation local when the recognizer supports it. Besides
            // matching the app's local-first boundary, this avoids unnecessary
            // Speech service/network XPC churn during short recording sessions.
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        didInstallInputTap = true

        self.audioEngine = audioEngine
        self.recognitionRequest = request
        self.speechRecognizer = recognizer
        isStopping = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.runningSessionID == sessionID else { return }
                if let result {
                    onPartial(result.bestTranscription.formattedString)
                }
                if let error, !self.isStopping {
                    self.cleanupAfterFailure()
                    onError(error.localizedDescription)
                    return
                }
                if result?.isFinal == true {
                    self.stop(reason: .manual)
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            cleanupAfterFailure()
            onError(error.localizedDescription)
        }
    }

    private func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            "语音识别权限已被拒绝，请在系统设置中允许康纳同学使用语音识别。"
        case .restricted:
            "当前设备或系统策略限制了语音识别。"
        case .notDetermined:
            "语音识别尚未授权。"
        case .authorized:
            "语音识别已授权。"
        @unknown default:
            "语音识别授权状态未知。"
        }
    }

    private func cleanupAfterFailure() {
        stop(reason: .appLifecycle)
    }

    private func cleanup() {
        didInstallInputTap = false
        runningSessionID = nil
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        audioEngine = nil
        isStopping = false
    }
}
