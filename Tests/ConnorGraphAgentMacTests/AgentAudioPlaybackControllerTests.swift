import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Agent Audio Playback Controller Tests")
@MainActor
struct AgentAudioPlaybackControllerTests {
    @Test func liveStreamStartsBufferingAndCannotSeek() {
        let controller = AgentAudioPlaybackController()
        controller.prepare(source: .liveStream(AgentAudioLiveStreamID(rawValue: "stream-1")))
        #expect(controller.state == .buffering)
        #expect(controller.state.canSeek == false)
    }

    @Test func liveStreamStateTransitionsRemainExplicit() {
        let controller = AgentAudioPlaybackController()
        controller.prepare(source: .liveStream(AgentAudioLiveStreamID(rawValue: "stream-1")))
        controller.updateLiveState(.playing)
        #expect(controller.state == .playing)
        controller.updateLiveState(.stalled)
        #expect(controller.state == .stalled)
        controller.updateLiveState(.cancelled)
        #expect(controller.state == .cancelled)
    }

    @Test func stopReleasesSourceAndResetsProgress() {
        let controller = AgentAudioPlaybackController()
        controller.prepare(source: .liveStream(AgentAudioLiveStreamID(rawValue: "stream-1")))
        controller.stop()
        #expect(controller.source == nil)
        #expect(controller.state == .idle)
        #expect(controller.currentTime == 0)
        #expect(controller.duration == 0)
    }

    @Test func missingFileTransitionsToFailed() {
        let controller = AgentAudioPlaybackController()
        controller.prepare(source: .file(URL(fileURLWithPath: "/tmp/connor-missing-audio-file.wav")))
        if case .failed = controller.state {
            // Expected.
        } else {
            Issue.record("Expected missing file to fail")
        }
    }
}
