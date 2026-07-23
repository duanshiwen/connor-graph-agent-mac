import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

private actor MiMOSpeechRequestRecorder {
    private(set) var request: AgentHTTPRequest?
    func record(_ request: AgentHTTPRequest) { self.request = request }
}

private struct MiMOSpeechHTTPClient: AgentHTTPClient {
    var response: AgentHTTPResponse
    let recorder: MiMOSpeechRequestRecorder

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        await recorder.record(request)
        return response
    }
}

@Suite("Xiaomi MiMo speech synthesis service")
struct XiaomiMiMOSpeechSynthesisServiceTests {
    @Test func sendsOfficialVoiceDesignContractAndDecodesWAV() async throws {
        let wav = Data("RIFF-test-wave".utf8)
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["audio": ["data": wav.base64EncodedString()]]]]
        ])
        let recorder = MiMOSpeechRequestRecorder()
        var service = XiaomiMiMOSpeechSynthesisService(client: MiMOSpeechHTTPClient(
            response: AgentHTTPResponse(statusCode: 200, body: responseBody),
            recorder: recorder
        ))

        let result = try await service.synthesize(
            markdown: "# 结论\n\n**任务已经完成。**",
            personality: .balancedDefault,
            voiceGender: .female,
            configuration: configuration()
        )

        #expect(result == wav)
        let request = try #require(await recorder.request)
        #expect(request.url.absoluteString == "https://api.xiaomimimo.com/v1/chat/completions")
        #expect(request.headers["Authorization"] == "Bearer secret")
        let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["model"] as? String == "mimo-v2.5-tts-voicedesign")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["user", "assistant"])
        #expect(messages[0]["content"]?.contains("青年女性") == true)
        #expect(messages[0]["content"]?.contains("平衡、理性且温和") == true)
        #expect(messages[1]["content"] == "结论\n任务已经完成。")
        let audio = try #require(body["audio"] as? [String: Any])
        #expect(audio["format"] as? String == "wav")
        #expect(audio["optimize_text_preview"] as? Bool == false)
    }

    @Test func supportsAPIKeyHeaderAndSurfacesProviderMessage() async throws {
        let recorder = MiMOSpeechRequestRecorder()
        var service = XiaomiMiMOSpeechSynthesisService(client: MiMOSpeechHTTPClient(
            response: AgentHTTPResponse(
                statusCode: 401,
                body: Data(#"{"error":{"message":"invalid key"}}"#.utf8)
            ),
            recorder: recorder
        ))
        var apiKeyConfiguration = configuration()
        apiKeyConfiguration.apiKeyHeaderKind = .apiKey

        await #expect(throws: XiaomiMiMOSpeechSynthesisError.providerRejected(statusCode: 401, message: "invalid key")) {
            try await service.synthesize(
                markdown: "你好",
                personality: .balancedDefault,
                voiceGender: .male,
                configuration: apiKeyConfiguration
            )
        }
        #expect(await recorder.request?.headers["api-key"] == "secret")
    }

    @Test func rejectsEmptySpokenTextBeforeCallingProvider() async {
        let recorder = MiMOSpeechRequestRecorder()
        var service = XiaomiMiMOSpeechSynthesisService(client: MiMOSpeechHTTPClient(
            response: AgentHTTPResponse(statusCode: 200, body: Data()),
            recorder: recorder
        ))

        await #expect(throws: XiaomiMiMOSpeechSynthesisError.emptyText) {
            try await service.synthesize(
                markdown: "  \n",
                personality: .balancedDefault,
                voiceGender: .male,
                configuration: configuration()
            )
        }
        #expect(await recorder.request == nil)
    }

    private func configuration() -> XiaomiMiMOSpeechConfiguration {
        XiaomiMiMOSpeechConfiguration(
            baseURL: URL(string: "https://api.xiaomimimo.com/v1")!,
            apiKey: "secret"
        )
    }
}
