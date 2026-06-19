import Foundation

@MainActor
protocol SessionSpeechTranscribing: AnyObject {
    var runningSessionID: String? { get }

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    )

    func stop(reason: SessionSpeechTranscriptionStopReason)
}

enum SessionSpeechTranscriptionStopReason: Equatable, Sendable {
    case manual
    case leavingSession
    case deletedSession
    case appLifecycle
}

@MainActor
final class SessionSpeechTranscriptionCoordinator {
    static let backgroundTaskKind = "speech_transcription"

    var transcriber: SessionSpeechTranscribing
    var onStatusChange: ((SessionSpeechTranscriptionStatus) -> Void)?
    var onTaskUpdate: ((AppSessionBackgroundTask) -> Void)?
    private(set) var status: SessionSpeechTranscriptionStatus = .idle {
        didSet { onStatusChange?(status) }
    }

    private var activeRunID: UUID?
    private var activeTask: AppSessionBackgroundTask?
    private var draftBaseText: String = ""
    private var lastRecognizedText: String = ""
    private var userEditedRecognizedText: String?
    private var lastGeneratedDraft: String = ""
    private var setDraft: ((String, String) -> Void)?

    init(transcriber: SessionSpeechTranscribing) {
        self.transcriber = transcriber
    }

    func isRunning(sessionID: String?) -> Bool {
        guard let sessionID else { return false }
        return status.runningSessionID == sessionID
    }

    @discardableResult
    func toggle(
        selectedSessionID: String?,
        currentDraft: String,
        setDraft: @escaping (String, String) -> Void
    ) -> AppSessionBackgroundTask? {
        guard let selectedSessionID else { return nil }
        if isRunning(sessionID: selectedSessionID) {
            return stop(reason: .manual)
        }
        if status.isRunning {
            _ = stop(reason: .leavingSession)
        }
        return start(sessionID: selectedSessionID, currentDraft: currentDraft, setDraft: setDraft)
    }

    @discardableResult
    func start(
        sessionID: String,
        currentDraft: String,
        setDraft: @escaping (String, String) -> Void
    ) -> AppSessionBackgroundTask {
        let runID = UUID()
        let task = AppSessionBackgroundTask(
            sessionID: sessionID,
            kind: Self.backgroundTaskKind,
            title: "实时语音转文字",
            detail: "正在把麦克风语音实时写入当前会话输入框",
            status: .running,
            payloadJSON: "{\"runID\":\"\(runID.uuidString)\"}"
        )
        activeRunID = runID
        activeTask = task
        draftBaseText = currentDraft
        lastGeneratedDraft = currentDraft
        self.setDraft = setDraft
        status = .running(sessionID: sessionID, taskID: task.id)

        transcriber.start(
            sessionID: sessionID,
            onPartial: { [weak self] text in
                self?.applyPartial(text, sessionID: sessionID, runID: runID)
            },
            onError: { [weak self] message in
                self?.fail(message: message, sessionID: sessionID, runID: runID)
            }
        )

        return task
    }

    func noteUserEditedDraft(sessionID: String?, draft: String) {
        guard let sessionID, status.runningSessionID == sessionID else { return }
        guard draft != lastGeneratedDraft else { return }

        // Speech partial results are cumulative for the current recognition run.
        // If the user edits text inside the generated speech region, keep the
        // original pre-speech base so the next partial replaces the speech
        // region instead of appending the full cumulative transcript again.
        if !lastRecognizedText.isEmpty, draft.hasPrefix(generatedSpeechPrefix()) {
            userEditedRecognizedText = String(draft.dropFirst(generatedSpeechPrefix().count))
            lastGeneratedDraft = draft
            return
        }

        // If the user edited outside the generated region, treat their current
        // composer content as the new base for future dictated text.
        draftBaseText = draft
        lastRecognizedText = ""
        userEditedRecognizedText = nil
        lastGeneratedDraft = draft
    }

    @discardableResult
    func stopIfRunningForLeavingSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        guard let sessionID, status.runningSessionID == sessionID else { return nil }
        return stop(reason: .leavingSession)
    }

    @discardableResult
    func stopIfRunningForDeletedSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        guard let sessionID, status.runningSessionID == sessionID else { return nil }
        return stop(reason: .deletedSession)
    }

    @discardableResult
    func stop(reason: SessionSpeechTranscriptionStopReason) -> AppSessionBackgroundTask? {
        guard var task = activeTask else {
            status = .idle
            return nil
        }

        transcriber.stop(reason: reason)
        task.status = statusForStopReason(reason)
        task.detail = detailForStopReason(reason)
        task.updatedAt = Date()

        reset()
        return task
    }

    private func applyPartial(_ partialText: String, sessionID: String, runID: UUID) {
        guard activeRunID == runID, status.runningSessionID == sessionID else { return }
        let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = displayTextForPartial(trimmed)
        let nextDraft = renderDraft(withRecognizedText: displayText)
        lastRecognizedText = trimmed
        if userEditedRecognizedText != nil {
            userEditedRecognizedText = displayText
        }
        lastGeneratedDraft = nextDraft
        setDraft?(sessionID, nextDraft)
    }

    private func displayTextForPartial(_ recognizedText: String) -> String {
        guard let userEditedRecognizedText, recognizedText.hasPrefix(lastRecognizedText) else {
            self.userEditedRecognizedText = nil
            return recognizedText
        }

        let suffix = recognizedText.dropFirst(lastRecognizedText.count)
        return userEditedRecognizedText + suffix
    }

    private func renderDraft(withRecognizedText recognizedText: String) -> String {
        if recognizedText.isEmpty {
            return draftBaseText
        }
        if draftBaseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recognizedText
        }
        return generatedSpeechPrefix() + recognizedText
    }

    private func generatedSpeechPrefix() -> String {
        if draftBaseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return draftBaseText + "\n\n"
    }

    private func fail(message: String, sessionID: String, runID: UUID) {
        guard activeRunID == runID, status.runningSessionID == sessionID else { return }
        var failedTask = activeTask
        failedTask?.status = .failed
        failedTask?.detail = "语音输入失败"
        failedTask?.errorMessage = message
        failedTask?.updatedAt = Date()
        activeTask = failedTask
        transcriber.stop(reason: .appLifecycle)
        status = .failed(message: message)
        if let failedTask {
            onTaskUpdate?(failedTask)
        }
    }

    private func reset() {
        activeRunID = nil
        activeTask = nil
        draftBaseText = ""
        lastRecognizedText = ""
        userEditedRecognizedText = nil
        lastGeneratedDraft = ""
        setDraft = nil
        status = .idle
    }

    private func statusForStopReason(_ reason: SessionSpeechTranscriptionStopReason) -> AppSessionBackgroundTaskStatus {
        switch reason {
        case .manual: .succeeded
        case .leavingSession, .deletedSession, .appLifecycle: .interrupted
        }
    }

    private func detailForStopReason(_ reason: SessionSpeechTranscriptionStopReason) -> String {
        switch reason {
        case .manual: "语音输入已停止"
        case .leavingSession: "离开会话，已自动停止语音输入"
        case .deletedSession: "会话已删除，语音输入已自动停止"
        case .appLifecycle: "应用生命周期变化，语音输入已自动停止"
        }
    }
}
