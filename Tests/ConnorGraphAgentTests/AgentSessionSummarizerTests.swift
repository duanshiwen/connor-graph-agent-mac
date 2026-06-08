import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphSearch

private actor PromptRecorder {
    private(set) var prompt: String?

    func record(_ prompt: String) {
        self.prompt = prompt
    }
}

private struct CapturingSummaryProvider: LLMProvider, Sendable {
    let recorder: PromptRecorder

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        await recorder.record(prompt)
        return LLMResponse(text: "Summary: graph memory and SQLite persistence.", citations: [])
    }
}

@Test func agentSessionSummarizerBuildsTranscriptPromptAndSummaryMetadata() async throws {
    let recorder = PromptRecorder()
    let provider = CapturingSummaryProvider(recorder: recorder)
    let summarizer = AgentSessionSummarizer(provider: provider)
    let session = AgentSession(
        id: "session-1",
        title: "Graph memory",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "How should chat persistence work?", createdAt: Date(timeIntervalSince1970: 1_000)),
            AgentMessage(id: "message-2", role: .assistant, content: "Store sessions and messages in SQLite.", createdAt: Date(timeIntervalSince1970: 2_000))
        ],
        createdAt: Date(timeIntervalSince1970: 500),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )

    let summary = try await summarizer.summarize(session: session)
    let prompt = try #require(await recorder.prompt)

    #expect(prompt.contains("Summarize this chat session"))
    #expect(prompt.contains("User: How should chat persistence work?"))
    #expect(prompt.contains("Assistant: Store sessions and messages in SQLite."))
    #expect(summary.sessionID == "session-1")
    #expect(summary.content == "Summary: graph memory and SQLite persistence.")
    #expect(summary.sourceMessageCount == 2)
    #expect(summary.lastMessageID == "message-2")
}
