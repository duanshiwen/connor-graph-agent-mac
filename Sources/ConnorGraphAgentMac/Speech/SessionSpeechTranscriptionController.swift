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
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stop(reason: .appLifecycle)
        runningSessionID = sessionID

        requestMicrophoneAccessIfNeeded { [weak self] microphoneGranted in
            Task { @MainActor in
                guard let self, self.runningSessionID == sessionID else { return }
                guard microphoneGranted else {
                    self.cleanupAfterFailure()
                    onError("麦克风权限已被拒绝，请在系统设置中允许康纳同学访问麦克风。")
                    return
                }
                self.requestSpeechRecognitionAccessIfNeeded(sessionID: sessionID, onPartial: onPartial, onError: onError)
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
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            handleSpeechAuthorizationStatus(currentStatus, sessionID: sessionID, onPartial: onPartial, onError: onError)
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            Task { @MainActor in
                self?.handleSpeechAuthorizationStatus(authorizationStatus, sessionID: sessionID, onPartial: onPartial, onError: onError)
            }
        }
    }

    private func handleSpeechAuthorizationStatus(
        _ authorizationStatus: SFSpeechRecognizerAuthorizationStatus,
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        guard runningSessionID == sessionID else { return }
        guard authorizationStatus == .authorized else {
            cleanupAfterFailure()
            onError(authorizationMessage(for: authorizationStatus))
            return
        }
        startAuthorizedRecognition(sessionID: sessionID, onPartial: onPartial, onError: onError)
    }

    private func startAuthorizedRecognition(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
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
        // Do not force on-device recognition by default. Apple documents this
        // flag as a hard network-prevention setting rather than a general
        // quality/performance recommendation. Some macOS locale/model
        // combinations advertise partial support but fail immediately for live
        // audio, which makes the session appear to start and then stop. Let the
        // recognizer choose the available path so live dictation remains stable.

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            cleanupAfterFailure()
            onError("麦克风输入格式不可用，请检查系统麦克风权限和输入设备。")
            return
        }
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
                // Keep the session-level dictation running until the user stops
                // it, leaves the session, or an actual error occurs. For live
                // audio, `isFinal` only means the current recognition request has
                // produced a final hypothesis; treating it as a user stop makes
                // short pauses look like the microphone immediately turns off.
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
