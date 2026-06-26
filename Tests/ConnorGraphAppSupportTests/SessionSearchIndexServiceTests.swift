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
        try await service.rebuild(sessions: [noise, target])

        let results = try await service.search(query: "雅加达 豪华酒店", limit: 3)

        #expect(results.first?.id == "session-target")
        #expect(results.first?.messageCount == 2)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSearchIndexServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("session-search.sqlite")
    }
}
