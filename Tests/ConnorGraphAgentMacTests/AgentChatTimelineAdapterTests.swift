import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Agent Chat Timeline Adapter Tests")
struct AgentChatTimelineAdapterTests {
    @Test func adapterPreservesStableTimelineIDsAndKinds() {
        let messages = [
            AgentMessage(id: "user-1", role: .user, content: "你好", createdAt: Date(timeIntervalSince1970: 100)),
            AgentMessage(id: "assistant-1", role: .assistant, content: "你好，我是康纳同学。", createdAt: Date(timeIntervalSince1970: 101))
        ]
        let timeline = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: Date(timeIntervalSince1970: 200))

        let items = AgentChatTimelineAdapter().items(from: timeline)

        #expect(items.map(\.id) == timeline.map(\.id))
        #expect(items.contains { $0.kind == .timestamp })
        #expect(items.contains { $0.kind == .message })
        #expect(items.contains { $0.kind == .process })
    }
}
