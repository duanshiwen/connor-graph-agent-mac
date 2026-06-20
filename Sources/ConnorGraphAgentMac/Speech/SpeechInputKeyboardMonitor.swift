import AppKit
import Foundation

struct SpeechInputKeyboardMonitorState: Equatable, Sendable {
    var isOptionDown = false
    var isSpaceDown = false
    var isRecording = false
    var isSpaceHoldEnabled = false
}

enum SpeechInputKeyboardAction: Equatable, Sendable {
    case none
    case begin
    case end
    case consumeOnly
}

struct SpeechInputKeyboardMonitorReducer: Sendable {
    static func optionChanged(isDown: Bool, state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isOptionDown != isDown else { return .none }
        state.isOptionDown = isDown
        if isDown {
            guard !state.isRecording else { return .none }
            state.isRecording = true
            return .begin
        }
        guard state.isRecording else { return .none }
        state.isRecording = false
        return .end
    }

    static func spaceKeyDown(isRepeat: Bool, state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isSpaceHoldEnabled else { return .none }
        if isRepeat { return .consumeOnly }
        guard !state.isSpaceDown else { return .consumeOnly }
        state.isSpaceDown = true
        guard !state.isRecording else { return .consumeOnly }
        state.isRecording = true
        return .begin
    }

    static func spaceKeyUp(state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        guard state.isSpaceHoldEnabled else { return .none }
        guard state.isSpaceDown else { return .consumeOnly }
        state.isSpaceDown = false
        guard state.isRecording else { return .consumeOnly }
        state.isRecording = false
        return .end
    }

    static func cancel(state: inout SpeechInputKeyboardMonitorState) -> SpeechInputKeyboardAction {
        let shouldEnd = state.isRecording
        state.isOptionDown = false
        state.isSpaceDown = false
        state.isRecording = false
        return shouldEnd ? .end : .none
    }
}

@MainActor
final class SpeechInputKeyboardMonitor {
    private var monitor: Any?
    private var state: SpeechInputKeyboardMonitorState
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    init(spaceHoldEnabled: Bool = false, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.state = SpeechInputKeyboardMonitorState(isSpaceHoldEnabled: spaceHoldEnabled)
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        perform(SpeechInputKeyboardMonitorReducer.cancel(state: &state))
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            let isOptionDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            perform(SpeechInputKeyboardMonitorReducer.optionChanged(isDown: isOptionDown, state: &state))
            return event
        case .keyDown where event.keyCode == 49:
            let action = SpeechInputKeyboardMonitorReducer.spaceKeyDown(isRepeat: event.isARepeat, state: &state)
            perform(action)
            return action == .none ? event : nil
        case .keyUp where event.keyCode == 49:
            let action = SpeechInputKeyboardMonitorReducer.spaceKeyUp(state: &state)
            perform(action)
            return action == .none ? event : nil
        default:
            return event
        }
    }

    private func perform(_ action: SpeechInputKeyboardAction) {
        switch action {
        case .begin: onBegin()
        case .end: onEnd()
        case .none, .consumeOnly: break
        }
    }
}
