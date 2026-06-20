import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Session Speech Transcription Coordinator Tests")
struct SessionSpeechTranscriptionCoordinatorTests {
    @Test func beginHoldToTalkCreatesRunningTaskAndPublishesProvisionalPartial() {
        var draftBySession: [String: String] = ["session-1": "已有内容"]
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)

        let task = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: draftBySession["session-1", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )

        #expect(task?.sessionID == "session-1")
        #expect(task?.kind == SessionSpeechTranscriptionCoordinator.backgroundTaskKind)
        #expect(task?.status == .running)
        #expect(coordinator.isRunning(sessionID: "session-1"))
        #expect(coordinator.status.isRecording)

        transcriber.emitPartial("你好 Connor")

        #expect(provisionalBySession["session-1"] == "你好 Connor")
        #expect(draftBySession["session-1"] == "已有内容")
    }

    @Test func partialHypothesisReplacesProvisionalLiveRegionInsteadOfAppendingDuplicateText() {
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { _, _ in },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )

        transcriber.emitPartial("你现在可以说中文")
        transcriber.emitPartial("你现在可以说中文了")

        #expect(provisionalBySession["session-1"] == "你现在可以说中文了")
    }

    @Test func finishHoldToTalkEntersFinalizingThenFinalCommitsDraftAndClearsProvisional() {
        var draftBySession: [String: String] = ["session-1": "已有内容"]
        var provisionalBySession: [String: String] = [:]
        var updatedTasks: [AppSessionBackgroundTask] = []
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        coordinator.onTaskUpdate = { updatedTasks.append($0) }
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "已有内容",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )
        transcriber.emitPartial("临时识别")

        let finalizing = coordinator.finishHoldToTalk()

        #expect(finalizing?.detail == "正在整理最终识别结果")
        #expect(coordinator.status == .idle)
        #expect(transcriber.stopReasons == [.manual])
        #expect(draftBySession["session-1"] == "已有内容\n\n临时识别")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(updatedTasks.last?.status == .succeeded)
        #expect(updatedTasks.last?.detail == "语音输入已完成")
    }

    @Test func finalResultReplacesPartialWhenRecognizerProvidesBetterText() {
        var draftBySession: [String: String] = ["session-1": ""]
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )

        transcriber.emitPartial("临时 结果")
        _ = coordinator.finishHoldToTalk()
        transcriber.emitFinal("最终结果更准确")

        #expect(draftBySession["session-1"] == "最终结果更准确")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(coordinator.status == .idle)
    }

    @Test func finalizationTimeoutKeepsPartialWhenFinalDoesNotArrive() async throws {
        var draftBySession: [String: String] = ["session-1": ""]
        var updatedTasks: [AppSessionBackgroundTask] = []
        var statuses: [SessionSpeechTranscriptionStatus] = []
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber, finalizationTimeoutNanoseconds: 1_000_000)
        coordinator.onTaskUpdate = { updatedTasks.append($0) }
        coordinator.onStatusChange = { statuses.append($0) }
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("可用的 partial")
        _ = coordinator.finishHoldToTalk()

        #expect(coordinator.status.isFinalizing)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(draftBySession["session-1"] == "可用的 partial")
        #expect(coordinator.status == .idle)
        #expect(statuses.last == .idle)
        #expect(updatedTasks.last?.status == .succeeded)
        #expect(updatedTasks.last?.detail == "最终识别超时，已使用实时识别结果")
    }

    @Test func beginNewRecognitionCancelsPreviousFinalizingRun() {
        var updatedTasks: [AppSessionBackgroundTask] = []
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        coordinator.onTaskUpdate = { updatedTasks.append($0) }
        _ = coordinator.beginHoldToTalk(selectedSessionID: "session-1", currentDraft: "", setDraft: { _, _ in })
        transcriber.emitPartial("上一轮")
        _ = coordinator.finishHoldToTalk()

        let nextTask = coordinator.beginHoldToTalk(selectedSessionID: "session-1", currentDraft: "", setDraft: { _, _ in })

        #expect(updatedTasks.last?.status == .interrupted)
        #expect(updatedTasks.last?.detail == "新的语音输入已开始，上一轮已取消")
        #expect(nextTask?.status == .running)
        #expect(coordinator.status.isRecording)
        #expect(transcriber.stopReasons == [.manual, .appLifecycle])
    }

    @Test func cancelCurrentRunInterruptsFinalizingAndClearsState() {
        var updatedTasks: [AppSessionBackgroundTask] = []
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        coordinator.onTaskUpdate = { updatedTasks.append($0) }
        _ = coordinator.beginHoldToTalk(selectedSessionID: "session-1", currentDraft: "", setDraft: { _, _ in })
        _ = coordinator.finishHoldToTalk()

        let cancelled = coordinator.cancelCurrentRun(detail: "发送消息，已取消未完成的语音整理")

        #expect(cancelled?.status == .interrupted)
        #expect(updatedTasks.last?.detail == "发送消息，已取消未完成的语音整理")
        #expect(coordinator.status == .idle)
        #expect(transcriber.stopReasons == [.manual, .appLifecycle])
    }

    @Test func repeatedFinishWhileFinalizingDoesNotRestartStopOrTimeout() {
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(selectedSessionID: "session-1", currentDraft: "", setDraft: { _, _ in })
        let first = coordinator.finishHoldToTalk()
        let second = coordinator.finishHoldToTalk()

        #expect(first?.id == second?.id)
        #expect(coordinator.status.isFinalizing)
        #expect(transcriber.stopReasons == [.manual])
    }

    @Test func finalFailurePathKeepsPartialWhenFinalTextIsEmpty() {
        var draftBySession: [String: String] = ["session-1": ""]
        let transcriber = FakeSessionSpeechTranscriber(emitFinalOnStop: false)
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("可用的 partial")
        _ = coordinator.finishHoldToTalk()
        transcriber.emitFinal("")

        #expect(draftBySession["session-1"] == "可用的 partial")
    }

    @Test func leavingSessionInterruptsTranscriptionAndIgnoresLatePartialResults() {
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { _, _ in },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )

        let stopped = coordinator.stopIfRunningForLeavingSession("session-1")
        transcriber.emitPartial("迟到的识别")

        #expect(stopped?.status == .interrupted)
        #expect(stopped?.detail == "离开会话，已自动停止语音输入")
        #expect(transcriber.stopReasons == [.leavingSession])
        #expect(provisionalBySession["session-1"] == nil)
    }

    @Test func beginWhileAlreadyRecordingSameSessionDoesNotStartDuplicateRun() {
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { _, _ in }
        )

        let duplicate = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { _, _ in }
        )

        #expect(duplicate == nil)
        #expect(transcriber.startCount == 1)
    }

    @Test func transcriberErrorPublishesFailedStatusAndTaskUpdate() {
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        var statuses: [SessionSpeechTranscriptionStatus] = []
        var updatedTasks: [AppSessionBackgroundTask] = []
        coordinator.onStatusChange = { statuses.append($0) }
        coordinator.onTaskUpdate = { updatedTasks.append($0) }

        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { _, _ in }
        )
        transcriber.emitError("麦克风不可用")

        #expect(statuses.last == .failed(message: "麦克风不可用"))
        #expect(updatedTasks.last?.status == .failed)
        #expect(updatedTasks.last?.errorMessage == "麦克风不可用")
        #expect(transcriber.stopReasons == [.appLifecycle])
    }
}

private final class FakeSessionSpeechTranscriber: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?
    private(set) var stopReasons: [SessionSpeechTranscriptionStopReason] = []
    private(set) var startCount = 0
    private let emitFinalOnStop: Bool
    private var latestPartial = ""
    private var onPartial: (@MainActor @Sendable (String) -> Void)?
    private var onFinal: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (String) -> Void)?

    init(emitFinalOnStop: Bool = true) {
        self.emitFinalOnStop = emitFinalOnStop
    }

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onFinal: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        startCount += 1
        runningSessionID = sessionID
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onError = onError
    }

    func stop(reason: SessionSpeechTranscriptionStopReason) {
        stopReasons.append(reason)
        runningSessionID = nil
        if reason == .manual, emitFinalOnStop {
            onFinal?(latestPartial)
        }
    }

    func emitPartial(_ text: String) {
        latestPartial = text
        onPartial?(text)
    }

    func emitFinal(_ text: String) {
        onFinal?(text)
    }

    func emitError(_ message: String) {
        onError?(message)
    }
}
