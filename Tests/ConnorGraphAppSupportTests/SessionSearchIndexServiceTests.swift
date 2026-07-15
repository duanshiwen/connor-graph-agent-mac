import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Session Search Index Service Tests")
struct SessionSearchIndexServiceTests {
    @Test func sessionSearchReturnsMatchingSessionFromIndex() async throws {
        let service = try SessionSearchIndexService(databaseURL: temporaryDatabaseURL())
        let target = AgentSession(
            id: "session-target",
            title: "出差雅加达奢华酒店规划",
            messages: [
                AgentMessage(role: .user, content: "我下个月去雅加达，希望住豪华酒店和商务套房。"),
                AgentMessage(role: .assistant, content: "可以按商圈、机场距离和早餐质量筛选。")
            ],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let noise = AgentSession(
            id: "session-noise",
            title: "杭州咖啡记录",
            messages: [AgentMessage(role: .user, content: "今天喝了手冲咖啡。")],
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        _ = try await service.bootstrapIfEmpty(sessions: [noise, target])

        let results = try await service.search(query: "雅加达 豪华酒店", limit: 3)

        #expect(results.first?.id == "session-target")
        #expect(results.first?.messageCount == 2)
    }

    @Test func bootstrapOnlyRunsWhenIndexIsEmptyAndRemovalIsExplicit() async throws {
        let service = try SessionSearchIndexService(databaseURL: temporaryDatabaseURL())
        let original = AgentSession(
            id: "session-original",
            title: "原始标题",
            messages: [AgentMessage(role: .user, content: "索引内容")],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let removed = AgentSession(
            id: "session-removed",
            title: "待删除",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let initial = try await service.bootstrapIfEmpty(sessions: [original, removed])
        let unchanged = try await service.bootstrapIfEmpty(sessions: [original, removed])
        var updated = original
        updated.title = "更新后的标题"
        updated.updatedAt = Date(timeIntervalSince1970: 3_000)
        try await service.upsert(session: updated)
        try await service.remove(sessionID: removed.id)
        let updatedResults = try await service.search(query: "更新后的标题", limit: 3)
        let removedResults = try await service.search(query: "待删除", limit: 3)

        #expect(initial == SessionSearchIndexSynchronizationResult(upsertedCount: 2, removedCount: 0, unchangedCount: 0))
        #expect(unchanged == SessionSearchIndexSynchronizationResult(upsertedCount: 0, removedCount: 0, unchangedCount: 2))
        #expect(updatedResults.first?.id == updated.id)
        #expect(removedResults.isEmpty)
    }

    @Test func upsertRefreshesChangedContentWithoutClearingOtherSessions() async throws {
        let service = try SessionSearchIndexService(databaseURL: temporaryDatabaseURL())
        let stable = AgentSession(
            id: "session-stable",
            title: "稳定保留",
            messages: [AgentMessage(role: .user, content: "不会被清空的索引")]
        )
        var changed = AgentSession(
            id: "session-changed",
            title: "内容更新",
            messages: [AgentMessage(role: .user, content: "旧关键词")]
        )
        _ = try await service.bootstrapIfEmpty(sessions: [stable, changed])
        changed.messages = [AgentMessage(role: .user, content: "新关键词")]

        try await service.upsert(session: changed)

        let stableResults = try await service.search(query: "不会被清空", limit: 3)
        let changedResults = try await service.search(query: "新关键词", limit: 3)
        #expect(stableResults.first?.id == stable.id)
        #expect(changedResults.first?.id == changed.id)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSearchIndexServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("session-search.sqlite")
    }
}
