@preconcurrency import AVFoundation
import Foundation
import Speech

private final class SpeechAudioSampleBufferForwarder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer?(sampleBuffer)
    }
}

@MainActor
final class SessionSpeechTranscriptionController: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?

    private let localeIdentifier: String?
    private let captureQueue = DispatchQueue(label: "com.shiwen.connor.speech.capture")

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var sampleBufferForwarder: SpeechAudioSampleBufferForwarder?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
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
        guard runningSessionID != nil || captureSession != nil || recognitionRequest != nil || recognitionTask != nil else { return }
        isStopping = true
        runningSessionID = nil

        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        sampleBufferForwarder?.onSampleBuffer = nil

        let sessionToStop = captureSession
        captureQueue.async {
            if sessionToStop?.isRunning == true {
                sessionToStop?.stopRunning()
            }
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

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

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            cleanupAfterFailure()
            onError("没有可用的麦克风输入设备，请连接或启用系统输入设备后再试。")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()

        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            guard captureSession.canAddInput(audioInput) else {
                captureSession.commitConfiguration()
                cleanupAfterFailure()
                onError("无法添加麦克风输入，请检查系统输入设备。")
                return
            }
            captureSession.addInput(audioInput)
        } catch {
            captureSession.commitConfiguration()
            cleanupAfterFailure()
            onError(error.localizedDescription)
            return
        }

        let audioOutput = AVCaptureAudioDataOutput()
        guard captureSession.canAddOutput(audioOutput) else {
            captureSession.commitConfiguration()
            cleanupAfterFailure()
            onError("无法添加麦克风音频输出，请检查系统输入设备。")
            return
        }

        let forwarder = SpeechAudioSampleBufferForwarder()
        forwarder.onSampleBuffer = { [weak request] sampleBuffer in
            request?.appendAudioSampleBuffer(sampleBuffer)
        }
        audioOutput.setSampleBufferDelegate(forwarder, queue: captureQueue)
        captureSession.addOutput(audioOutput)
        captureSession.commitConfiguration()

        self.captureSession = captureSession
        self.audioOutput = audioOutput
        self.sampleBufferForwarder = forwarder
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
                // For session-level dictation, keep listening until the user
                // stops, leaves/deletes the session, or Speech reports an error.
                // Do not stop just because one recognition result is final.
            }
        }

        captureQueue.async { [weak captureSession] in
            captureSession?.startRunning()
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
        captureSession = nil
        audioOutput = nil
        sampleBufferForwarder = nil
        runningSessionID = nil
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        isStopping = false
    }
}
