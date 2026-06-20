import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Session Speech Transcription Coordinator Tests")
struct SessionSpeechTranscriptionCoordinatorTests {
    @Test func startCreatesRunningTaskAndAppliesPartialTranscriptToDraft() {
        var draftBySession: [String: String] = ["session-1": "已有内容"]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)

        let task = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: draftBySession["session-1", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        #expect(task?.sessionID == "session-1")
        #expect(task?.kind == SessionSpeechTranscriptionCoordinator.backgroundTaskKind)
        #expect(task?.status == .running)
        #expect(coordinator.isRunning(sessionID: "session-1"))

        transcriber.emitPartial("你好 Connor")

        #expect(draftBySession["session-1"] == "已有内容\n\n你好 Connor")
    }

    @Test func partialHypothesisReplacesLiveRegionInsteadOfAppendingDuplicateText() {
        var draftBySession: [String: String] = ["session-1": ""]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("你现在可以说中文")
        transcriber.emitPartial("你现在可以说中文了")

        #expect(draftBySession["session-1"] == "你现在可以说中文了")
    }

    @Test func userMiddleEditKeepsEditedSpeechRegionAndAppendsOnlyNewSuffix() {
        var draftBySession: [String: String] = ["session-1": ""]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("你现在是不是可以说中文了")
        #expect(draftBySession["session-1"] == "你现在是不是可以说中文了")

        draftBySession["session-1"] = "你现在可以说中文了"
        coordinator.noteUserEditedDraft(sessionID: "session-1", draft: "你现在可以说中文了")
        transcriber.emitPartial("你现在是不是可以说中文了 App 呢棒了太棒了")

        #expect(draftBySession["session-1"] == "你现在可以说中文了 App 呢棒了太棒了")
    }

    @Test func manualStopCompletesRunningTaskAndKeepsDraftText() {
        var draftBySession: [String: String] = ["session-1": ""]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )
        transcriber.emitPartial("请帮我总结")

        let stopped = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: draftBySession["session-1", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        #expect(stopped?.status == .succeeded)
        #expect(stopped?.detail == "语音输入已停止")
        #expect(transcriber.stopReasons == [.manual])
        #expect(coordinator.status == .idle)
        #expect(draftBySession["session-1"] == "请帮我总结")
    }

    @Test func leavingSessionInterruptsTranscriptionAndIgnoresLatePartialResults() {
        var draftBySession: [String: String] = ["session-1": "", "session-2": "新会话"]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        let stopped = coordinator.stopIfRunningForLeavingSession("session-1")
        transcriber.emitPartial("迟到的识别")

        #expect(stopped?.status == .interrupted)
        #expect(stopped?.detail == "离开会话，已自动停止语音输入")
        #expect(transcriber.stopReasons == [.leavingSession])
        #expect(draftBySession["session-1"] == "")
        #expect(draftBySession["session-2"] == "新会话")
    }

    @Test func partialFromOldRunDoesNotOverwriteNewSessionDraft() {
        var draftBySession: [String: String] = ["session-1": "", "session-2": ""]
        let firstTranscriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: firstTranscriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )
        _ = coordinator.stopIfRunningForLeavingSession("session-1")

        coordinator.transcriber = FakeSessionSpeechTranscriber()
        _ = coordinator.toggle(
            selectedSessionID: "session-2",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )
        firstTranscriber.emitPartial("旧会话迟到内容")

        #expect(draftBySession["session-1"] == "")
        #expect(draftBySession["session-2"] == "")
    }

    @Test func startingNewSessionAfterStopDoesNotCarryPreviousHypothesis() {
        var draftBySession: [String: String] = ["session-1": "", "session-2": ""]
        let firstTranscriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: firstTranscriber)
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )
        firstTranscriber.emitPartial("上一轮内容")
        _ = coordinator.toggle(
            selectedSessionID: "session-1",
            currentDraft: draftBySession["session-1", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        let secondTranscriber = FakeSessionSpeechTranscriber()
        coordinator.transcriber = secondTranscriber
        _ = coordinator.toggle(
            selectedSessionID: "session-2",
            currentDraft: draftBySession["session-2", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )
        secondTranscriber.emitPartial("新的会话内容")
        firstTranscriber.emitPartial("上一轮内容迟到")

        #expect(draftBySession["session-1"] == "上一轮内容")
        #expect(draftBySession["session-2"] == "新的会话内容")
    }

    @Test func transcriberErrorPublishesFailedStatusAndTaskUpdate() {
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        var statuses: [SessionSpeechTranscriptionStatus] = []
        var updatedTasks: [AppSessionBackgroundTask] = []
        coordinator.onStatusChange = { statuses.append($0) }
        coordinator.onTaskUpdate = { updatedTasks.append($0) }

        _ = coordinator.toggle(
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
    private var onPartial: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (String) -> Void)?

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        runningSessionID = sessionID
        self.onPartial = onPartial
        self.onError = onError
    }

    func stop(reason: SessionSpeechTranscriptionStopReason) {
        stopReasons.append(reason)
        runningSessionID = nil
    }

    func emitPartial(_ text: String) {
        onPartial?(text)
    }

    func emitError(_ message: String) {
        onError?(message)
    }
}
