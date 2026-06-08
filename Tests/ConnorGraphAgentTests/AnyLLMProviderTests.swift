import Testing
import ConnorGraphAgent
import ConnorGraphSearch

@Test func anyLLMProviderDelegatesCompletion() async throws {
    let provider = AnyLLMProvider { prompt, context in
        LLMResponse(text: "prompt=\(prompt); context=\(context.query)", citations: ["node:1"])
    }
    let context = AgentContext(query: "memory", items: [])

    let response = try await provider.complete(prompt: "hello", context: context)

    #expect(response.text == "prompt=hello; context=memory")
    #expect(response.citations == ["node:1"])
}
