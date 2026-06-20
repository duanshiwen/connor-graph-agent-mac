import Testing
@testable import ConnorGraphAgentMac

@Suite("Speech Input Keyboard Monitor Tests")
struct SpeechInputKeyboardMonitorTests {
    @Test func optionDownBeginsAndOptionUpEnds() {
        var state = SpeechInputKeyboardMonitorState()

        let begin = SpeechInputKeyboardMonitorReducer.optionChanged(isDown: true, state: &state)
        let repeated = SpeechInputKeyboardMonitorReducer.optionChanged(isDown: true, state: &state)
        let end = SpeechInputKeyboardMonitorReducer.optionChanged(isDown: false, state: &state)

        #expect(begin == .begin)
        #expect(repeated == .none)
        #expect(end == .end)
        #expect(!state.isRecording)
    }

    @Test func spaceHoldIsIgnoredByDefault() {
        var state = SpeechInputKeyboardMonitorState(isSpaceHoldEnabled: false)

        let action = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: false, state: &state)

        #expect(action == .none)
        #expect(!state.isRecording)
    }

    @Test func enabledSpaceHoldBeginsConsumesRepeatsAndEnds() {
        var state = SpeechInputKeyboardMonitorState(isSpaceHoldEnabled: true)

        let begin = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: false, state: &state)
        let repeatAction = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: true, state: &state)
        let end = SpeechInputKeyboardMonitorReducer.spaceKeyUp(state: &state)

        #expect(begin == .begin)
        #expect(repeatAction == .consumeOnly)
        #expect(end == .end)
        #expect(!state.isRecording)
    }

    @Test func cancelEndsActiveKeyboardRecording() {
        var state = SpeechInputKeyboardMonitorState(isSpaceHoldEnabled: true)
        _ = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: false, state: &state)

        let action = SpeechInputKeyboardMonitorReducer.cancel(state: &state)

        #expect(action == .end)
        #expect(!state.isRecording)
        #expect(!state.isSpaceDown)
        #expect(!state.isOptionDown)
    }
}
