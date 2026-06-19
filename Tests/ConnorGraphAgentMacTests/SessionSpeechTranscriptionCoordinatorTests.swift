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
}

private final class FakeSessionSpeechTranscriber: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?
    private(set) var stopReasons: [SessionSpeechTranscriptionStopReason] = []
    private var onPartial: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    func start(
        sessionID: String,
        onPartial: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
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
}
