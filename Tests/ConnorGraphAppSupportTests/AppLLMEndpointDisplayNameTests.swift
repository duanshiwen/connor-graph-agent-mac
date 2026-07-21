import Testing
import ConnorGraphAppSupport

@Suite("LLM Endpoint Display Name Tests")
struct AppLLMEndpointDisplayNameTests {
    @Test func defaultConnectionNameRemovesSchemePathPortAndCommonSuffix() {
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://api.openai.com/v1", fallback: "OpenAI") == "api.openai")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://token-plan-cn.xiaomimimo.com/v1", fallback: "Xiaomi MiMo") == "token-plan-cn.xiaomimimo")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://api.individual.githubcopilot.com", fallback: "GitHub Copilot") == "api.individual.githubcopilot")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://cnai.connor.run", fallback: "Connor AI") == "cnai.connor")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://openrouter.ai/api/v1", fallback: "OpenRouter") == "openrouter")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "http://localhost:11434/v1", fallback: "本地模型") == "localhost")
    }

    @Test func defaultConnectionNameFallsBackWhenEndpointIsEmpty() {
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "", fallback: "其他提供商") == "其他提供商")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "   ", fallback: "未命名连接") == "未命名连接")
    }

    @Test func protocolConnectionNameUsesPrimaryDomainAndProtocol() {
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://api.xiaomimimo.com/v1", fallback: "Xiaomi MiMo", protocolName: "Anthropic") == "xiaomimimo.Anthropic")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://eu.api.openai.com/v1", fallback: "OpenAI", protocolName: "OpenAI") == "openai.OpenAI")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "https://gateway.example.com.cn/v1", fallback: "Example", protocolName: "OpenAI") == "example.OpenAI")
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "http://localhost:11434/v1", fallback: "本地模型", protocolName: "OpenAI") == "localhost.OpenAI")
    }

    @Test func protocolConnectionNameFallsBackWithProtocolWhenEndpointIsEmpty() {
        #expect(AppLLMEndpointDisplayName.defaultConnectionName(from: "", fallback: "其他提供商", protocolName: "Anthropic") == "其他提供商.Anthropic")
    }

    @Test func hostPreservesCurrentEndpointSubtitleBehavior() {
        #expect(AppLLMEndpointDisplayName.host(from: "https://token-plan-cn.xiaomimimo.com/v1") == "token-plan-cn.xiaomimimo.com")
        #expect(AppLLMEndpointDisplayName.host(from: "https://cnai.connor.run") == "cnai.connor.run")
        #expect(AppLLMEndpointDisplayName.host(from: "") == "未设置 endpoint")
    }
}
