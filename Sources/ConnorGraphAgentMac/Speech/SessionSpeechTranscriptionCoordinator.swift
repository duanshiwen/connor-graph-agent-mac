import Foundation

@MainActor
protocol SessionSpeechTranscribing: AnyObject {
    var runningSessionID: String? { get }

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onFinal: @escaping @MainActor @Sendable (String) -> Void,
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

enum SessionSpeechTranscriptionStatus: Equatable, Sendable {
    case idle
    case recording(sessionID: String, taskID: String)
    case finalizing(sessionID: String, taskID: String)
    case failed(message: String)

    var runningSessionID: String? {
        switch self {
        case .recording(let sessionID, _), .finalizing(let sessionID, _): sessionID
        case .idle, .failed: nil
        }
    }

    var runningTaskID: String? {
        switch self {
        case .recording(_, let taskID), .finalizing(_, let taskID): taskID
        case .idle, .failed: nil
        }
    }

    var isRunning: Bool {
        runningSessionID != nil
    }

    var isRecording: Bool {
        guard case .recording = self else { return false }
        return true
    }

    var isFinalizing: Bool {
        guard case .finalizing = self else { return false }
        return true
    }
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

    // Mature streaming-ASR UI model:
    // - draftBaseText is stable text that existed before the current dictation run.
    // - liveSpeechText is the replaceable interim hypothesis region for this run.
    // - lastSpeechHypothesis is the raw previous SFSpeech partial hypothesis.
    // - userEditedSpeechText preserves user edits inside the live region and only
    //   accepts later hypothesis suffixes when the recognizer continues from the
    //   previous hypothesis. This matches the common final-results + current
    //   interim-hypothesis model used by Web Speech/UWP continuous dictation.
    private var draftBaseText: String = ""
    private var lastSpeechHypothesis: String = ""
    private var liveSpeechText: String = ""
    private var userEditedSpeechText: String?
    private var lastGeneratedDraft: String = ""
    private var provisionalSpeechText: String = ""
    private var setDraft: ((String, String) -> Void)?
    private var setProvisionalTranscript: ((String, String?) -> Void)?
    private let finalizationTimeoutNanoseconds: UInt64
    private var finalizationTimeoutTask: Task<Void, Never>?

    init(transcriber: SessionSpeechTranscribing, finalizationTimeoutNanoseconds: UInt64 = 1_500_000_000) {
        self.transcriber = transcriber
        self.finalizationTimeoutNanoseconds = finalizationTimeoutNanoseconds
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
            return finishHoldToTalk(reason: .manual)
        }
        return beginHoldToTalk(selectedSessionID: selectedSessionID, currentDraft: currentDraft, setDraft: setDraft)
    }

    @discardableResult
    func beginHoldToTalk(
        selectedSessionID: String?,
        currentDraft: String,
        setDraft: @escaping (String, String) -> Void,
        setProvisionalTranscript: ((String, String?) -> Void)? = nil
    ) -> AppSessionBackgroundTask? {
        guard let selectedSessionID else { return nil }
        if status.isRecording, status.runningSessionID == selectedSessionID { return nil }
        if status.isRunning {
            _ = cancelCurrentRun(detail: "新的语音输入已开始，上一轮已取消")
        }
        return start(
            sessionID: selectedSessionID,
            currentDraft: currentDraft,
            setDraft: setDraft,
            setProvisionalTranscript: setProvisionalTranscript
        )
    }

    @discardableResult
    func start(
        sessionID: String,
        currentDraft: String,
        setDraft: @escaping (String, String) -> Void,
        setProvisionalTranscript: ((String, String?) -> Void)? = nil
    ) -> AppSessionBackgroundTask {
        let runID = UUID()
        let task = AppSessionBackgroundTask(
            sessionID: sessionID,
            kind: Self.backgroundTaskKind,
            title: "按住说话",
            detail: "正在听写语音，松开后会短暂整理最终识别结果",
            status: .running,
            payloadJSON: "{\"runID\":\"\(runID.uuidString)\"}"
        )
        activeRunID = runID
        activeTask = task
        draftBaseText = currentDraft
        lastSpeechHypothesis = ""
        liveSpeechText = ""
        userEditedSpeechText = nil
        lastGeneratedDraft = currentDraft
        provisionalSpeechText = ""
        self.setDraft = setDraft
        self.setProvisionalTranscript = setProvisionalTranscript
        status = .recording(sessionID: sessionID, taskID: task.id)

        transcriber.start(
            sessionID: sessionID,
            onPartial: { [weak self] text in
                self?.applyPartial(text, sessionID: sessionID, runID: runID)
            },
            onFinal: { [weak self] text in
                self?.applyFinal(text, sessionID: sessionID, runID: runID)
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

        let prefix = generatedSpeechPrefix()
        if !lastSpeechHypothesis.isEmpty, draft.hasPrefix(prefix) {
            liveSpeechText = String(draft.dropFirst(prefix.count))
            userEditedSpeechText = liveSpeechText
            lastGeneratedDraft = draft
            return
        }

        draftBaseText = draft
        lastSpeechHypothesis = ""
        liveSpeechText = ""
        userEditedSpeechText = nil
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
    func finishHoldToTalk(reason: SessionSpeechTranscriptionStopReason = .manual) -> AppSessionBackgroundTask? {
        guard reason == .manual else { return stop(reason: reason) }
        guard var task = activeTask, let sessionID = status.runningSessionID else {
            status = .idle
            return nil
        }
        if status.isFinalizing {
            return task
        }

        task.detail = "正在整理最终识别结果"
        task.updatedAt = Date()
        activeTask = task
        status = .finalizing(sessionID: sessionID, taskID: task.id)
        scheduleFinalizationTimeout(sessionID: sessionID, runID: activeRunID)
        transcriber.stop(reason: reason)
        return task
    }

    @discardableResult
    func cancelCurrentRun(detail: String = "语音输入已取消") -> AppSessionBackgroundTask? {
        guard var task = activeTask else {
            status = .idle
            return nil
        }
        transcriber.stop(reason: .appLifecycle)
        task.status = .interrupted
        task.detail = detail
        task.updatedAt = Date()
        setProvisionalTranscript?(task.sessionID, nil)
        reset()
        onTaskUpdate?(task)
        return task
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
        let hypothesis = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        liveSpeechText = mergedLiveSpeechText(for: hypothesis)
        lastSpeechHypothesis = hypothesis
        provisionalSpeechText = liveSpeechText
        setProvisionalTranscript?(sessionID, liveSpeechText)
    }

    private func applyFinal(_ finalText: String, sessionID: String, runID: UUID) {
        guard activeRunID == runID, status.runningSessionID == sessionID else { return }
        let finalSpeechText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let committedSpeechText = finalSpeechText.isEmpty ? provisionalSpeechText : finalSpeechText
        let nextDraft = renderDraft(withLiveSpeechText: committedSpeechText)
        lastGeneratedDraft = nextDraft
        setDraft?(sessionID, nextDraft)
        setProvisionalTranscript?(sessionID, nil)

        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil

        var completedTask = activeTask
        completedTask?.status = .succeeded
        completedTask?.detail = "语音输入已完成"
        completedTask?.updatedAt = Date()
        reset()
        if let completedTask {
            onTaskUpdate?(completedTask)
        }
    }

    private func mergedLiveSpeechText(for hypothesis: String) -> String {
        guard let userEditedSpeechText else {
            return hypothesis
        }

        guard hypothesis.hasPrefix(lastSpeechHypothesis) else {
            self.userEditedSpeechText = nil
            return hypothesis
        }

        let suffix = hypothesis.dropFirst(lastSpeechHypothesis.count)
        let merged = userEditedSpeechText + suffix
        self.userEditedSpeechText = merged
        return merged
    }

    private func renderDraft(withLiveSpeechText speechText: String) -> String {
        if speechText.isEmpty {
            return draftBaseText
        }
        if draftBaseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return speechText
        }
        return generatedSpeechPrefix() + speechText
    }

    private func generatedSpeechPrefix() -> String {
        if draftBaseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return draftBaseText + "\n\n"
    }

    private func scheduleFinalizationTimeout(sessionID: String, runID: UUID?) {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.finalizationTimeoutNanoseconds ?? 1_500_000_000)
            } catch {
                return
            }
            await MainActor.run {
                self?.completeWithPartialAfterFinalizationTimeout(sessionID: sessionID, runID: runID)
            }
        }
    }

    func forceFinalizationTimeoutForTesting() {
        guard let sessionID = status.runningSessionID else { return }
        completeWithPartialAfterFinalizationTimeout(sessionID: sessionID, runID: activeRunID)
    }

    private func completeWithPartialAfterFinalizationTimeout(sessionID: String, runID: UUID?) {
        guard activeRunID == runID, status.runningSessionID == sessionID, status.isFinalizing else { return }
        let nextDraft = renderDraft(withLiveSpeechText: provisionalSpeechText)
        lastGeneratedDraft = nextDraft
        setDraft?(sessionID, nextDraft)
        setProvisionalTranscript?(sessionID, nil)

        var completedTask = activeTask
        completedTask?.status = .succeeded
        completedTask?.detail = "最终识别超时，已使用实时识别结果"
        completedTask?.updatedAt = Date()
        reset()
        if let completedTask {
            onTaskUpdate?(completedTask)
        }
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
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        activeRunID = nil
        activeTask = nil
        draftBaseText = ""
        lastSpeechHypothesis = ""
        liveSpeechText = ""
        userEditedSpeechText = nil
        lastGeneratedDraft = ""
        provisionalSpeechText = ""
        setDraft = nil
        setProvisionalTranscript = nil
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
