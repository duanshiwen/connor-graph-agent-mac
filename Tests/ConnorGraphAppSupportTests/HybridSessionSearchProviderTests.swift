import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private struct StubIndexSearchProvider: SessionSearchProviding {
    let results: [SessionSearchResult]
    func search(query: String, limit: Int) async throws -> [SessionSearchResult] {
        results
    }
}

@Suite("Hybrid Session Search Provider Tests")
struct HybridSessionSearchProviderTests {
    private func makeSession(id: String, title: String, content: String, updatedAt: TimeInterval) -> AgentSession {
        AgentSession(
            id: id,
            title: title,
            messages: [
                AgentMessage(role: .user, content: content, createdAt: Date(timeIntervalSince1970: updatedAt - 60)),
            ],
            createdAt: Date(timeIntervalSince1970: updatedAt - 120),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    @Test func fallsBackToFullScanWhenIndexReturnsNothing() async throws {
        let provider = HybridSessionSearchProvider(index: StubIndexSearchProvider(results: [])) {
            [
                makeSession(id: "s1", title: "旧会话", content: "我上次说要买路由器了", updatedAt: 1_000),
                makeSession(id: "s2", title: "无关会话", content: "今天天气不错", updatedAt: 2_000),
            ]
        }

        let results = try await provider.search(query: "路由器", limit: 10)

        #expect(results.count == 1)
        #expect(results.first?.id == "s1")
        #expect(results.first?.snippet.contains("路由器") == true)
        #expect(results.first?.messageCount == 1)
    }

    @Test func mergesIndexHitsWithFallbackAndDeduplicates() async throws {
        let provider = HybridSessionSearchProvider(index: StubIndexSearchProvider(results: [
            SessionSearchResult(id: "s1", title: "旧会话", snippet: "路由器", updatedAt: Date(timeIntervalSince1970: 1_000), messageCount: 1)
        ])) {
            [
                makeSession(id: "s1", title: "旧会话", content: "我上次说要买路由器了", updatedAt: 1_000),
                makeSession(id: "s3", title: "另一段", content: "路由器还是买了", updatedAt: 3_000),
            ]
        }

        let results = try await provider.search(query: "路由器", limit: 10)

        #expect(results.map(\.id).sorted() == ["s1", "s3"])
        // 按更新时间倒序：s3(3s) 在前
        #expect(results.first?.id == "s3")
    }

    @Test func returnsIndexHitsDirectlyWhenTheyFillTheLimit() async throws {
        let provider = HybridSessionSearchProvider(index: StubIndexSearchProvider(results: [
            SessionSearchResult(id: "s1", title: "a", snippet: "x", updatedAt: Date(timeIntervalSince1970: 1), messageCount: 1),
            SessionSearchResult(id: "s2", title: "b", snippet: "x", updatedAt: Date(timeIntervalSince1970: 2), messageCount: 1)
        ])) {
            [
                makeSession(id: "s3", title: "c", content: "路由器", updatedAt: 3),
            ]
        }

        let results = try await provider.search(query: "路由器", limit: 2)

        #expect(results.count == 2)
        #expect(results.map(\.id) == ["s1", "s2"])
    }
}
