import AppKit
import Foundation
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

    @Test func finishHoldToTalkImmediatelyCommitsPartialAndClearsProvisional() {
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

        let completed = coordinator.finishHoldToTalk()

        #expect(completed?.detail == "语音输入已完成")
        #expect(coordinator.status == .idle)
        #expect(transcriber.stopReasons == [.manual])
        #expect(draftBySession["session-1"] == "已有内容\n\n临时识别")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(updatedTasks.last?.status == .succeeded)
        #expect(updatedTasks.last?.detail == "语音输入已完成")
    }

    @Test func finishHoldToTalkInsertsPartialAtCapturedCaretRange() {
        var draftBySession: [String: String] = ["session-1": "你好世界"]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "你好世界",
            speechInsertionRange: NSRange(location: 2, length: 0),
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial(" Connor ")
        _ = coordinator.finishHoldToTalk()

        #expect(draftBySession["session-1"] == "你好Connor世界")
    }

    @Test func finishHoldToTalkReplacesCapturedSelectionRange() {
        var draftBySession: [String: String] = ["session-1": "请把这里替换掉"]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "请把这里替换掉",
            speechInsertionRange: NSRange(location: 2, length: 2),
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("中间")
        _ = coordinator.finishHoldToTalk()

        #expect(draftBySession["session-1"] == "请把中间替换掉")
    }

    @Test func finishHoldToTalkFallsBackToAppendWhenNoCapturedRangeExists() {
        var draftBySession: [String: String] = ["session-1": "已有内容"]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "已有内容",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("追加语音")
        _ = coordinator.finishHoldToTalk()

        #expect(draftBySession["session-1"] == "已有内容\n\n追加语音")
    }

    @Test func latePartialResultIsIgnoredAfterImmediateCommit() {
        var draftBySession: [String: String] = ["session-1": ""]
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber()
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
        #expect(draftBySession["session-1"] == "临时 结果")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(coordinator.status == .idle)
    }

    @Test func immediateCommitKeepsLatestPartial() {
        var draftBySession: [String: String] = ["session-1": ""]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)
        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft }
        )

        transcriber.emitPartial("可用的 partial")
        _ = coordinator.finishHoldToTalk()
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

    @Test func eachHoldToTalkRunStartsWithFreshSpeechCache() {
        var draftBySession: [String: String] = ["session-1": ""]
        var provisionalBySession: [String: String] = [:]
        let transcriber = FakeSessionSpeechTranscriber()
        let coordinator = SessionSpeechTranscriptionCoordinator(transcriber: transcriber)

        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: "",
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )
        transcriber.emitPartial("第一轮")
        _ = coordinator.finishHoldToTalk()

        transcriber.emitPartial("第一轮迟到 partial")
        #expect(draftBySession["session-1"] == "第一轮")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(transcriber.hasActiveCallbacks == false)

        _ = coordinator.beginHoldToTalk(
            selectedSessionID: "session-1",
            currentDraft: draftBySession["session-1", default: ""],
            setDraft: { sessionID, draft in draftBySession[sessionID] = draft },
            setProvisionalTranscript: { sessionID, text in
                if let text { provisionalBySession[sessionID] = text } else { provisionalBySession.removeValue(forKey: sessionID) }
            }
        )
        transcriber.emitPartial("第二轮")
        _ = coordinator.finishHoldToTalk()

        #expect(draftBySession["session-1"] == "第一轮\n\n第二轮")
        #expect(provisionalBySession["session-1"] == nil)
        #expect(transcriber.startCount == 2)
    }
}

@MainActor
@Suite("Composer Text Selection Tracker Tests")
struct ComposerTextSelectionTrackerTests {
    @Test func selectionChangesUpdateTrackerWithoutMutatingBindingState() {
        var text = "你好世界"
        let tracker = ComposerTextSelectionTracker()
        let coordinator = SafeChatComposerTextView.Coordinator(
            text: .init(get: { text }, set: { text = $0 }),
            selectionTracker: tracker
        )
        let textView = NSTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))

        #expect(tracker.selectedRange == NSRange(location: 2, length: 0))
        #expect(text == "你好世界")
    }
}

private final class FakeSessionSpeechTranscriber: SessionSpeechTranscribing {
    private(set) var runningSessionID: String?
    private(set) var stopReasons: [SessionSpeechTranscriptionStopReason] = []
    private(set) var startCount = 0
    private var latestPartial = ""
    var hasActiveCallbacks: Bool { onPartial != nil || onError != nil }
    private var onPartial: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (String) -> Void)?

    func start(
        sessionID: String,
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        startCount += 1
        runningSessionID = sessionID
        latestPartial = ""
        self.onPartial = onPartial
        self.onError = onError
    }

    func stop(reason: SessionSpeechTranscriptionStopReason) {
        stopReasons.append(reason)
        runningSessionID = nil
        latestPartial = ""
        onPartial = nil
        onError = nil
    }

    func emitPartial(_ text: String) {
        guard onPartial != nil else { return }
        latestPartial = text
        onPartial?(text)
    }

    func emitError(_ message: String) {
        onError?(message)
    }
}
