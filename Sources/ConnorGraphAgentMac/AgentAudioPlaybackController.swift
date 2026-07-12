import AVFoundation
import Foundation
import Observation

struct AgentAudioLiveStreamID: Hashable, Sendable { var rawValue: String }

enum AgentAudioPlaybackSource: Equatable, Sendable {
    case file(URL)
    case liveStream(AgentAudioLiveStreamID)
}

enum AgentAudioPlaybackState: Equatable, Sendable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case stalled
    case completing
    case completed
    case failed(String)
    case cancelled

    var canSeek: Bool {
        switch self {
        case .playing, .paused, .completed: return true
        default: return false
        }
    }
}

@MainActor
@Observable
final class AgentAudioPlaybackController: NSObject, AVAudioPlayerDelegate {
    private(set) var source: AgentAudioPlaybackSource?
    private(set) var state: AgentAudioPlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func prepare(source: AgentAudioPlaybackSource) {
        stop()
        self.source = source
        switch source {
        case .file(let url):
            state = .loading
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.prepareToPlay()
                self.player = player
                duration = player.duration
                state = .paused
            } catch {
                state = .failed(error.localizedDescription)
            }
        case .liveStream:
            state = .buffering
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            state = .paused
            progressTask?.cancel()
        } else if player.play() {
            state = .playing
            startProgressUpdates()
        }
    }

    func seek(to time: TimeInterval) {
        guard case .file = source, let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        currentTime = player.currentTime
    }

    func updateLiveState(_ newState: AgentAudioPlaybackState) {
        guard case .liveStream = source else { return }
        state = newState
    }

    func transitionToCompletedFile(_ url: URL) { prepare(source: .file(url)) }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        player = nil
        source = nil
        state = .idle
        currentTime = 0
        duration = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedDuration = player.duration
        Task { @MainActor [weak self, finishedDuration] in
            self?.currentTime = finishedDuration
            self?.state = flag ? .completed : .failed("音频播放未正常完成")
            self?.progressTask?.cancel()
        }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let player = self.player, player.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }
}
