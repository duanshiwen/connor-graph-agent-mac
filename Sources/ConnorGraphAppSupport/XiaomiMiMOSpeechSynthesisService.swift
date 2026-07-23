import Foundation
import ConnorGraphAgent

public struct XiaomiMiMOSpeechConfiguration: Sendable, Equatable {
    public static let voiceDesignModel = "mimo-v2.5-tts-voicedesign"

    public var baseURL: URL
    public var apiKey: String
    public var extraHeaders: [String: String]
    public var apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind
    public var requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        apiKey: String,
        extraHeaders: [String: String] = [:],
        apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer,
        requestTimeout: TimeInterval = 300
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.apiKeyHeaderKind = apiKeyHeaderKind
        self.requestTimeout = requestTimeout
    }
}

public extension AppLLMSettingsRepository {
    func xiaomiMiMOSpeechConfiguration() throws -> XiaomiMiMOSpeechConfiguration? {
        let settings = try loadSettings()
        guard let connection = settings.xiaomiMiMOSpeechConnection,
              let apiKey = try apiKey(for: connection.id),
              !apiKey.isEmpty,
              let sourceURL = URL(string: connection.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = sourceURL.host?.lowercased()
        else { return nil }
        let endpoint: String
        switch host {
        case "api.xiaomimimo.com":
            endpoint = "https://api.xiaomimimo.com/v1"
        case "token-plan-cn.xiaomimimo.com":
            endpoint = "https://token-plan-cn.xiaomimimo.com/v1"
        default:
            return nil
        }
        guard let baseURL = URL(string: endpoint) else { return nil }
        return XiaomiMiMOSpeechConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            apiKeyHeaderKind: .apiKey
        )
    }
}

public enum XiaomiMiMOSpeechSynthesisError: Error, Sendable, Equatable, LocalizedError {
    case emptyText
    case invalidResponse
    case providerRejected(statusCode: Int, message: String?)
    case missingAudio
    case invalidAudioData

    public var errorDescription: String? {
        switch self {
        case .emptyText: "没有可朗读的回复内容。"
        case .invalidResponse: "MiMO 语音服务返回了无法识别的响应。"
        case let .providerRejected(statusCode, message):
            message.map { "MiMO 语音服务请求失败（HTTP \(statusCode)）：\($0)" }
                ?? "MiMO 语音服务请求失败（HTTP \(statusCode)）。"
        case .missingAudio: "MiMO 语音服务没有返回音频。"
        case .invalidAudioData: "MiMO 语音服务返回的音频数据无效。"
        }
    }
}

public enum ConnorVoiceDesignPromptBuilder {
    public static func prompt(
        personality: ConnorPersonalitySettings,
        voiceGender: ConnorVoiceGender,
        voiceProfile: ConnorVoiceProfile? = nil
    ) -> String {
        if let voiceProfile, let profile = try? voiceProfile.validated() {
            return customPrompt(profile: profile, voiceGender: voiceGender)
        }
        let effectivePersonality = personality.isEmpty ? .balancedDefault : personality
        let traits = effectivePersonality.traits.prefix(4).joined(separator: "、")
        let identity = traits.isEmpty
            ? effectivePersonality.summary
            : "\(effectivePersonality.summary)；核心特质是\(traits)"
        let communication = effectivePersonality.communicationStyle.isEmpty
            ? "表达清晰自然，先给结论再说明必要依据"
            : effectivePersonality.communicationStyle
        let tone = effectivePersonality.emotionalTone.isEmpty
            ? "沉稳、友善、真诚"
            : effectivePersonality.emotionalTone
        return """
        \(voiceGender.voiceDesignDescription)，普通话自然标准，声音清晰温润、质感平衡。人格底色是\(trimmed(identity, limit: 180))。说话时\(trimmed(communication, limit: 150))，整体情绪\(trimmed(tone, limit: 80))。语速适中，咬字清楚，停顿从容，像一位可靠而有分寸的长期协作伙伴。
        """
    }

    private static func customPrompt(profile: ConnorVoiceProfile, voiceGender: ConnorVoiceGender) -> String {
        var parts = [voiceGender.voiceDesignDescription, profile.summary]
        if !profile.ageRange.isEmpty { parts.append("听感年龄：\(profile.ageRange)") }
        if !profile.timbre.isEmpty { parts.append("音色质感：\(profile.timbre)") }
        if !profile.speakingStyle.isEmpty { parts.append("表达方式：\(profile.speakingStyle)") }
        if !profile.pace.isEmpty { parts.append("语速节奏：\(profile.pace)") }
        if !profile.accent.isEmpty { parts.append("发音要求：\(profile.accent)") }
        if !profile.emotionalTone.isEmpty { parts.append("情绪底色：\(profile.emotionalTone)") }
        return parts.joined(separator: "。") + "。"
    }

    private static func trimmed(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

public enum ConnorSpeechTextFormatter {
    public static func spokenText(from markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .components(separatedBy: .newlines)
            .map { line in
                let source = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { return "" }
                return (try? AttributedString(markdown: source))
                    .map { String($0.characters) } ?? source
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public struct XiaomiMiMOSpeechSynthesisService<Client: AgentHTTPClient>: Sendable {
    public var client: Client

    public init(client: Client) {
        self.client = client
    }

    public mutating func synthesize(
        markdown: String,
        personality: ConnorPersonalitySettings,
        voiceGender: ConnorVoiceGender,
        voiceProfile: ConnorVoiceProfile? = nil,
        configuration: XiaomiMiMOSpeechConfiguration
    ) async throws -> Data {
        let text = ConnorSpeechTextFormatter.spokenText(from: markdown)
        guard !text.isEmpty else { throw XiaomiMiMOSpeechSynthesisError.emptyText }

        let response = try await client.send(try makeRequest(
            text: text,
            personality: personality,
            voiceGender: voiceGender,
            voiceProfile: voiceProfile,
            configuration: configuration
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw XiaomiMiMOSpeechSynthesisError.providerRejected(
                statusCode: response.statusCode,
                message: Self.errorMessage(from: response.body)
            )
        }
        guard let payload = try? JSONDecoder().decode(ResponsePayload.self, from: response.body) else {
            throw XiaomiMiMOSpeechSynthesisError.invalidResponse
        }
        guard let encoded = payload.choices.first?.message.audio?.data, !encoded.isEmpty else {
            throw XiaomiMiMOSpeechSynthesisError.missingAudio
        }
        guard let audio = Data(base64Encoded: encoded), !audio.isEmpty else {
            throw XiaomiMiMOSpeechSynthesisError.invalidAudioData
        }
        return audio
    }

    private func makeRequest(
        text: String,
        personality: ConnorPersonalitySettings,
        voiceGender: ConnorVoiceGender,
        voiceProfile: ConnorVoiceProfile?,
        configuration: XiaomiMiMOSpeechConfiguration
    ) throws -> AgentHTTPRequest {
        let body: [String: Any] = [
            "model": XiaomiMiMOSpeechConfiguration.voiceDesignModel,
            "messages": [
                ["role": "user", "content": ConnorVoiceDesignPromptBuilder.prompt(personality: personality, voiceGender: voiceGender, voiceProfile: voiceProfile)],
                ["role": "assistant", "content": text]
            ],
            "audio": ["format": "wav", "optimize_text_preview": false]
        ]
        var headers = configuration.extraHeaders
        headers["Content-Type"] = "application/json"
        switch configuration.apiKeyHeaderKind {
        case .bearer: headers["Authorization"] = "Bearer \(configuration.apiKey)"
        case .apiKey: headers["api-key"] = configuration.apiKey
        }
        return AgentHTTPRequest(
            url: configuration.baseURL.appendingPathComponent("chat/completions"),
            method: "POST",
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            timeoutInterval: configuration.requestTimeout
        )
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error.message
    }

    private struct ResponsePayload: Decodable {
        var choices: [Choice]
        struct Choice: Decodable { var message: Message }
        struct Message: Decodable { var audio: Audio? }
        struct Audio: Decodable { var data: String }
    }

    private struct ErrorPayload: Decodable {
        var error: APIError
        struct APIError: Decodable { var message: String }
    }
}

public extension XiaomiMiMOSpeechSynthesisService where Client == URLSessionAgentHTTPClient {
    init() {
        self.init(client: URLSessionAgentHTTPClient())
    }
}
