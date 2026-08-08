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

private struct StubImTranscriptSearchProvider: ImTranscriptSearchProviding {
    let hits: [ImConversationSearchHit]

    func searchConversations(query: String, limit: Int) async throws -> [ImConversationSearchHit] {
        hits
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

    @Test func sessionSearchToolMergesSessionAndImConversationsSortedByRecency() async throws {
        let stub = StubSessionSearchProvider(results: [
            SessionSearchResult(
                id: "session-1",
                title: "伴侣选择讨论",
                snippet: "我们聊过择偶标准",
                updatedAt: Date(timeIntervalSince1970: 1_000),
                messageCount: 12
            )
        ])
        let imStub = StubImTranscriptSearchProvider(hits: [
            ImConversationSearchHit(
                conversation: ImConversation(
                    id: "im-group-1",
                    kind: .group,
                    title: "选型小组",
                    lastMessagePreview: "路由器型号定了吗",
                    lastMessageAt: 3_000_000,
                    updatedAt: 2_000_000
                ),
                snippet: "路由器型号定了吗"
            ),
            ImConversationSearchHit(
                conversation: ImConversation(
                    id: "im-peer-1",
                    kind: .peer,
                    title: "小明",
                    lastMessagePreview: "上次说的路由器",
                    lastMessageAt: 2_000_000,
                    updatedAt: 1_000_000
                ),
                snippet: "上次说的路由器"
            )
        ])
        let tool = SessionSearchTool(sessionSearch: stub, imTranscriptSearch: imStub)
        let context = AgentToolExecutionContext(
            runID: "run-session-search-im",
            sessionID: "session",
            groupID: "group",
            userPrompt: "路由器",
            toolCallID: "session-search-im",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(json: #"{"query":"路由器"}"#),
            context: context
        )
        let payload = try #require(result.contentJSON)
        let response = try JSONDecoder().decode(SessionSearchToolResponse.self, from: Data(payload.utf8))

        #expect(response.success)
        #expect(response.returnedItems == 3)
        #expect(response.totalItems == 3)
        // 按更新时间倒序：im_group(3s) → im_peer(2s) → session(1s)
        #expect(response.records.map(\.sessionID) == ["im-group-1", "im-peer-1", "session-1"])
        #expect(response.records.map(\.kind) == ["im_group", "im_peer", "session"])
        #expect(response.records.first?.title == "选型小组")
        #expect(result.citations.contains("im_group:im-group-1"))
        #expect(result.citations.contains("session:session-1"))
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
