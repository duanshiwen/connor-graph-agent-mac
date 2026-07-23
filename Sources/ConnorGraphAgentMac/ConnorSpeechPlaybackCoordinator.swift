import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport

enum ConnorSpeechPlaybackPhase: Equatable {
    case idle
    case loading(messageID: String)
    case playing(messageID: String)
    case failed(messageID: String, message: String)

    func isLoading(messageID: String) -> Bool {
        if case .loading(let activeID) = self { return activeID == messageID }
        return false
    }

    func isPlaying(messageID: String) -> Bool {
        if case .playing(let activeID) = self { return activeID == messageID }
        return false
    }
}

struct ConnorSpeechActionPresentation: Equatable {
    var isVisible: Bool
    var title: String
    var systemImage: String
    var accessibilityLabel: String
    var help: String
    var isLoading: Bool

    init(isAvailable: Bool, phase: ConnorSpeechPlaybackPhase, messageID: String) {
        isVisible = isAvailable
        isLoading = phase.isLoading(messageID: messageID)
        if isLoading {
            title = "生成中"
            systemImage = "speaker.wave.2"
            accessibilityLabel = "正在生成这条回复的语音，点击停止"
            help = "停止生成语音"
        } else if phase.isPlaying(messageID: messageID) {
            title = "停止"
            systemImage = "stop.fill"
            accessibilityLabel = "停止朗读这条助理回复"
            help = "停止朗读"
        } else {
            title = "朗读"
            systemImage = "speaker.wave.2"
            accessibilityLabel = "朗读这条助理回复"
            help = "使用 Xiaomi MiMo 朗读"
        }
    }
}

@MainActor
@Observable
final class ConnorSpeechPlaybackCoordinator {
    typealias Synthesizer = @Sendable (
        _ markdown: String,
        _ personality: ConnorPersonalitySettings,
        _ voiceGender: ConnorVoiceGender
    ) async throws -> Data

    private(set) var phase: ConnorSpeechPlaybackPhase = .idle
    @ObservationIgnored var isAvailable: () -> Bool = { false }
    @ObservationIgnored var reportError: (String) -> Void = { _ in }

    @ObservationIgnored private let synthesizer: Synthesizer
    @ObservationIgnored private let playback = AgentAudioPlaybackController()
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var synthesisTask: Task<Void, Never>?
    @ObservationIgnored private var playbackMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAudioURLs: [String: URL] = [:]
    @ObservationIgnored private var automaticallyReadMessageIDs = Set<String>()

    init(settingsRepository: AppLLMSettingsRepository, synthesizer: Synthesizer? = nil) {
        self.synthesizer = synthesizer ?? { markdown, personality, voiceGender in
            guard let configuration = try settingsRepository.xiaomiMiMOSpeechConfiguration() else {
                throw ConnorSpeechPlaybackError.unavailable
            }
            var service = XiaomiMiMOSpeechSynthesisService()
            return try await service.synthesize(
                markdown: markdown,
                personality: personality,
                voiceGender: voiceGender,
                configuration: configuration
            )
        }
    }

    func presentation(messageID: String) -> ConnorSpeechActionPresentation {
        ConnorSpeechActionPresentation(isAvailable: isAvailable(), phase: phase, messageID: messageID)
    }

    func toggle(messageID: String, markdown: String, personality: ConnorPersonalitySettings, personalityRevision: Int, voiceGender: ConnorVoiceGender) {
        if phase.isLoading(messageID: messageID) || phase.isPlaying(messageID: messageID) {
            stop()
            return
        }
        guard isAvailable() else { return }
        start(
            messageID: messageID,
            markdown: markdown,
            personality: personality,
            cacheKey: cacheKey(messageID: messageID, personalityRevision: personalityRevision, voiceGender: voiceGender),
            voiceGender: voiceGender
        )
    }

    func automaticallyRead(messageID: String, markdown: String, personality: ConnorPersonalitySettings, personalityRevision: Int, voiceGender: ConnorVoiceGender, enabled: Bool) {
        guard enabled,
              isAvailable(),
              automaticallyReadMessageIDs.insert(messageID).inserted
        else { return }
        start(
            messageID: messageID,
            markdown: markdown,
            personality: personality,
            cacheKey: cacheKey(messageID: messageID, personalityRevision: personalityRevision, voiceGender: voiceGender),
            voiceGender: voiceGender
        )
    }

    func stopIfUnavailable() {
        if !isAvailable() { stop() }
    }

    func stop() {
        generation &+= 1
        synthesisTask?.cancel()
        synthesisTask = nil
        playbackMonitorTask?.cancel()
        playbackMonitorTask = nil
        playback.stop()
        phase = .idle
    }

    func shutdown() {
        stop()
        for url in cachedAudioURLs.values { try? FileManager.default.removeItem(at: url) }
        cachedAudioURLs.removeAll()
        automaticallyReadMessageIDs.removeAll()
    }

    private func start(messageID: String, markdown: String, personality: ConnorPersonalitySettings, cacheKey: String, voiceGender: ConnorVoiceGender) {
        stop()
        let currentGeneration = generation
        if let cachedURL = cachedAudioURLs[cacheKey], FileManager.default.fileExists(atPath: cachedURL.path) {
            beginPlayback(url: cachedURL, messageID: messageID, generation: currentGeneration)
            return
        }

        phase = .loading(messageID: messageID)
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await synthesizer(markdown, personality, voiceGender)
                try Task.checkCancellation()
                guard generation == currentGeneration else { return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("connor-mimo-speech-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                try audio.write(to: url, options: .atomic)
                cachedAudioURLs[cacheKey] = url
                synthesisTask = nil
                beginPlayback(url: url, messageID: messageID, generation: currentGeneration)
            } catch is CancellationError {
                if generation == currentGeneration { phase = .idle }
            } catch {
                guard generation == currentGeneration else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                synthesisTask = nil
                phase = .failed(messageID: messageID, message: message)
                reportError(message)
            }
        }
    }

    private func beginPlayback(url: URL, messageID: String, generation currentGeneration: UInt64) {
        playback.prepare(source: .file(url))
        guard case .paused = playback.state else {
            failPlayback(messageID: messageID, message: "生成的语音无法播放。")
            return
        }
        playback.togglePlayback()
        guard playback.state == .playing else {
            failPlayback(messageID: messageID, message: "语音播放未能启动。")
            return
        }
        phase = .playing(messageID: messageID)
        monitorPlayback(messageID: messageID, generation: currentGeneration)
    }

    private func monitorPlayback(messageID: String, generation currentGeneration: UInt64) {
        playbackMonitorTask?.cancel()
        playbackMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == currentGeneration {
                switch playback.state {
                case .completed:
                    playbackMonitorTask = nil
                    phase = .idle
                    return
                case .failed(let message):
                    playbackMonitorTask = nil
                    failPlayback(messageID: messageID, message: message)
                    return
                default:
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    private func failPlayback(messageID: String, message: String) {
        phase = .failed(messageID: messageID, message: message)
        reportError(message)
    }

    private func cacheKey(messageID: String, personalityRevision: Int, voiceGender: ConnorVoiceGender) -> String {
        "\(messageID):\(personalityRevision):\(voiceGender.rawValue)"
    }
}

enum ConnorSpeechPlaybackError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "需要先启用带有效 API Key 的 Xiaomi MiMo 按量付费连接。"
    }
}
