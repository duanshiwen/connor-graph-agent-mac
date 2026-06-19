import Foundation
import Testing
@testable import ConnorGraphCore

@Suite("Session Attention Domain")
struct SessionAttentionDomainTests {
    @Test("legacy agent session JSON decodes with default read state")
    func legacyAgentSessionJSONDecodesWithDefaultReadState() throws {
        let json = """
        {
          "id": "legacy-session",
          "title": "Legacy Session",
          "messages": [],
          "createdAt": "2026-06-19T01:00:00Z",
          "updatedAt": "2026-06-19T02:00:00Z",
          "governance": {
            "status": "todo",
            "labels": [],
            "isArchived": false,
            "isFlagged": false
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(AgentSession.self, from: json)

        #expect(session.readState.highestLevel == .none)
        #expect(session.readState.unreadCount == 0)
        #expect(session.readState.updatedAt == session.updatedAt)
    }

    @Test("attention levels keep product severity order")
    func attentionLevelsKeepSeverityOrder() {
        #expect(SessionAttentionLevel.none < .unread)
        #expect(SessionAttentionLevel.unread < .emphasized)
        #expect(SessionAttentionLevel.emphasized < .actionable)
        #expect(SessionAttentionLevel.actionable < .interruptive)
        #expect(SessionAttentionLevel.actionable.shouldCountInDockBadge)
        #expect(!SessionAttentionLevel.emphasized.shouldRequestSystemNotification)
        #expect(SessionAttentionLevel.interruptive.shouldRequestSystemNotification)
    }

    @Test("initial read state is read and quiet")
    func initialReadStateIsReadAndQuiet() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = SessionReadState.initial(updatedAt: now)

        #expect(state.lastReadMessageID == nil)
        #expect(state.lastReadAt == nil)
        #expect(state.unreadCount == 0)
        #expect(state.highestLevel == .none)
        #expect(state.lastUnreadMessageID == nil)
        #expect(state.lastUnreadPreview == nil)
        #expect(state.updatedAt == now)
    }

    @Test("mark unread increments count and raises level")
    func markUnreadIncrementsCountAndRaisesLevel() {
        var state = SessionReadState.initial(updatedAt: Date(timeIntervalSince1970: 1_000))
        let updateTime = Date(timeIntervalSince1970: 2_000)

        state.markUnread(messageID: "m1", preview: "Hello", level: .emphasized, at: updateTime)

        #expect(state.unreadCount == 1)
        #expect(state.highestLevel == .emphasized)
        #expect(state.lastUnreadMessageID == "m1")
        #expect(state.lastUnreadPreview == "Hello")
        #expect(state.updatedAt == updateTime)
    }

    @Test("mark unread keeps highest level across multiple messages")
    func markUnreadKeepsHighestLevel() {
        var state = SessionReadState.initial()

        state.markUnread(messageID: "m1", preview: nil, level: .actionable, at: Date(timeIntervalSince1970: 2_000))
        state.markUnread(messageID: "m2", preview: "ordinary", level: .unread, at: Date(timeIntervalSince1970: 3_000))

        #expect(state.unreadCount == 2)
        #expect(state.highestLevel == .actionable)
        #expect(state.lastUnreadMessageID == "m2")
        #expect(state.lastUnreadPreview == "ordinary")
    }

    @Test("mark read clears unread state")
    func markReadClearsUnreadState() {
        var state = SessionReadState.initial()
        state.markUnread(messageID: "m1", preview: "Needs review", level: .interruptive, at: Date(timeIntervalSince1970: 2_000))
        let readTime = Date(timeIntervalSince1970: 4_000)

        state.markRead(messageID: "m1", at: readTime)

        #expect(state.lastReadMessageID == "m1")
        #expect(state.lastReadAt == readTime)
        #expect(state.unreadCount == 0)
        #expect(state.highestLevel == .none)
        #expect(state.lastUnreadMessageID == nil)
        #expect(state.lastUnreadPreview == nil)
        #expect(state.updatedAt == readTime)
    }
}
