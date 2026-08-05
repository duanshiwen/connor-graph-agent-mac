import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Connor Portable Session Merge")
struct ConnorPortableSessionMergeTests {
    @Test func staleRemoteSessionDoesNotClearLocalHistoryOrGovernance() {
        let local = AgentSession(
            id: "session",
            title: "本地会话",
            messages: [
                AgentMessage(id: "old-user", role: .user, content: "上一轮", createdAt: Date(timeIntervalSince1970: 1)),
                AgentMessage(id: "old-assistant", role: .assistant, content: "上一轮回复", createdAt: Date(timeIntervalSince1970: 2)),
                AgentMessage(id: "new-user", role: .user, content: "新消息", createdAt: Date(timeIntervalSince1970: 3)),
            ],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 20),
            governance: AgentSessionGovernanceMetadata(
                status: .inProgress,
                labels: [AgentSessionLabel(id: "important")],
                isArchived: false
            )
        )
        let staleRemote = ConnorPortableSession(AgentSession(
            id: "session",
            title: "远端旧会话",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 10),
            governance: AgentSessionGovernanceMetadata(status: .todo, labels: [], isArchived: false)
        ))

        let merged = staleRemote.merging(into: local)

        #expect(merged.title == "本地会话")
        #expect(merged.governance.status == .inProgress)
        #expect(merged.governance.labels.map(\.id) == ["important"])
        #expect(merged.messages.map(\.id) == ["old-user", "old-assistant", "new-user"])
    }

    @Test func newerRemoteSessionWinsGovernanceAndKeepsLocalOnlyMessages() {
        let localMessage = AgentMessage(
            id: "local",
            role: .user,
            content: "本地待同步",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let remoteMessage = AgentMessage(
            id: "remote",
            role: .assistant,
            content: "其他端消息",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let local = AgentSession(
            id: "session",
            messages: [localMessage],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let remote = ConnorPortableSession(AgentSession(
            id: "session",
            title: "远端新标题",
            messages: [remoteMessage],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 20),
            governance: AgentSessionGovernanceMetadata(
                status: .done,
                labels: [AgentSessionLabel(id: "priority")],
                isArchived: false
            )
        ))

        let merged = remote.merging(into: local)

        #expect(merged.title == "远端新标题")
        #expect(merged.governance.status == .done)
        #expect(merged.governance.labels.map(\.id) == ["priority"])
        #expect(merged.messages.map(\.id) == ["remote", "local"])
    }
}
