import Foundation
import AVFoundation
import Observation

/// 本地 TTS 朗读控制器（macOS 侧 AVSpeechSynthesizer 封装）。
///
/// - 供会话页顶栏「自动朗读」开关、消息气泡「朗读 / 停止」按钮以及
///   助理回复完成后的自动朗读共用同一个引擎与播放状态；
/// - 纯本地离线合成，不产生任何网络请求；
/// - 自动朗读开关跨启动持久化（UserDefaults）。
@MainActor
@Observable
final class AssistantSpeechController {
    /// 自动朗读 AI 回复的总开关（跨启动持久化）。
    var autoReadEnabled: Bool {
        didSet { UserDefaults.standard.set(autoReadEnabled, forKey: Self.autoReadEnabledKey) }
    }

    /// 是否正在朗读。
    private(set) var isSpeaking = false
    /// 当前正在朗读的消息 ID（用于消息气泡按钮展示「停止」态）。
    private(set) var speakingMessageID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechSynthesizerDelegateBridge()
    /// 当前正在播放的 utterance，用于回调时确认是不是本轮朗读。
    private weak var currentUtterance: AVSpeechUtterance?

    init(
        autoReadEnabled: Bool = UserDefaults.standard.object(forKey: AssistantSpeechController.autoReadEnabledKey) as? Bool ?? false
    ) {
        self.autoReadEnabled = autoReadEnabled
        delegateBridge.onFinished = { [weak self] utterance in
            Task { @MainActor in
                self?.finishSpeaking(utterance: utterance)
            }
        }
        delegateBridge.onCancelled = { [weak self] utterance in
            Task { @MainActor in
                self?.finishSpeaking(utterance: utterance)
            }
        }
        synthesizer.delegate = delegateBridge
    }

    /// 朗读一段文本。会先停止当前朗读；messageID 用于气泡按钮跟踪播放状态。
    func speak(_ text: String, messageID: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.preferredVoice
        utterance.rate = Self.speechRate
        currentUtterance = utterance
        speakingMessageID = messageID
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// 气泡按钮语义：正在朗读同一条消息则停止，否则切到该消息朗读。
    func toggleSpeak(_ text: String, messageID: String?) {
        if isSpeaking, speakingMessageID == messageID {
            stop()
        } else {
            speak(text, messageID: messageID)
        }
    }

    /// 立即停止朗读并复位播放状态。
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        speakingMessageID = nil
        currentUtterance = nil
    }

    private func finishSpeaking(utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        isSpeaking = false
        speakingMessageID = nil
        currentUtterance = nil
    }

    /// 优先使用系统简体中文语音，其次繁体中文，最后回退到默认语音。
    private static var preferredVoice: AVSpeechSynthesisVoice? {
        let preferredLanguages = ["zh-CN", "zh-TW", "zh-HK"]
        let voices = AVSpeechSynthesisVoice.speechVoices()
        for language in preferredLanguages {
            if let voice = voices.first(where: { $0.language == language }) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice()
    }

    /// 比系统默认语速略慢一点，长回复听感更从容。
    private static var speechRate: Float {
        AVSpeechUtteranceDefaultSpeechRate * 0.96
    }

    private static let autoReadEnabledKey = "AssistantSpeech.AutoReadEnabled"
}

/// AVSpeechSynthesizer 的代理桥接（回调线程不保证是主线程，统一切回主线程处理状态）。
///
/// macOS 26 SDK 起 `AVSpeechSynthesizerDelegate` 被标注为 `Sendable`，遵循它会隐式要求本类符合
/// `Sendable`。这里的两个闭包只在主线程的初始化阶段写入一次、之后只读，回调侧仅读取，因此用
/// `@unchecked Sendable` 显式声明并发安全由该使用契约保证。
private final class SpeechSynthesizerDelegateBridge: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinished: (AVSpeechUtterance) -> Void = { _ in }
    var onCancelled: (AVSpeechUtterance) -> Void = { _ in }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinished(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancelled(utterance)
    }
}

