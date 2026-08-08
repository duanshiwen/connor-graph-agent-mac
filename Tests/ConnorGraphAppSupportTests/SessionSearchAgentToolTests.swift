import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private struct StubSessionSearchProvider: SessionSearchProviding {
    let results: [SessionSearchResult]

    func search(query: String, limit: Int) async throws -> [SessionSearchResult] {
        results
    }
}

@Suite("Session Search Agent Tool Tests")
struct SessionSearchAgentToolTests {
    @Test func sessionSearchToolReturnsMappedTranscriptHits() async throws {
        let stub = StubSessionSearchProvider(results: [
            SessionSearchResult(
                id: "session-1",
                title: "伴侣选择讨论",
                snippet: "我们聊过择偶标准",
                updatedAt: Date(timeIntervalSince1970: 1_000),
                messageCount: 12
            )
        ])
        let tool = SessionSearchTool(sessionSearch: stub)
        let context = AgentToolExecutionContext(
            runID: "run-session-search",
            sessionID: "session",
            groupID: "group",
            userPrompt: "择偶",
            toolCallID: "session-search",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(json: #"{"query":"择偶"}"#),
            context: context
        )
        let payload = try #require(result.contentJSON)
        let response = try JSONDecoder().decode(SessionSearchToolResponse.self, from: Data(payload.utf8))

        #expect(result.toolName == "session_search")
        #expect(response.success)
        #expect(response.totalItems == 1)
        #expect(response.records.first?.sessionID == "session-1")
        #expect(response.records.first?.title == "伴侣选择讨论")
        #expect(response.records.first?.snippet.contains("择偶") == true)
        #expect(response.records.first?.messageCount == 12)
        #expect(result.citations == ["session:session-1"])
    }

    @Test func sessionSearchToolRejectsEmptyQuery() async throws {
        let tool = SessionSearchTool(sessionSearch: StubSessionSearchProvider(results: []))
        let context = AgentToolExecutionContext(
            runID: "run-session-search-empty",
            sessionID: "session",
            groupID: "group",
            userPrompt: "",
            toolCallID: "session-search-empty",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
        await #expect(throws: AgentToolError.self) {
            _ = try await tool.execute(
                arguments: AgentToolArguments(json: #"{"query":""}"#),
                context: context
            )
        }
    }
}
