import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Agent Chat Timeline Adapter Tests")
struct AgentChatTimelineAdapterTests {
    @Test func adapterPreservesStableTimelineIDsAndKinds() {
        let messages = sampleMessages()
        let timeline = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: Date(timeIntervalSince1970: 200))

        let items = AgentChatTimelineAdapter().items(from: timeline)

        #expect(items.map(\.id) == timeline.map(\.id))
        #expect(items.contains { $0.kind == .timestamp })
        #expect(items.contains { $0.kind == .message })
        #expect(items.contains { $0.kind == .process })
    }

    @Test func adapterInsertsUnreadMarkerBeforeBoundaryItem() {
        let messages = sampleMessages()
        let timeline = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: Date(timeIntervalSince1970: 200))
        let boundary = CommercialChatUnreadBoundary(beforeItemID: "assistant-1", unreadCount: 2)

        let items = AgentChatTimelineAdapter().items(from: timeline, unreadBoundary: boundary)

        let markerIndex = items.firstIndex { $0.kind == .unreadSeparator }
        let assistantIndex = items.firstIndex { $0.id == "assistant-1" }
        #expect(markerIndex != nil)
        #expect(assistantIndex != nil)
        #expect(markerIndex! < assistantIndex!)
        #expect(items[markerIndex!].id == "unread-boundary-before-assistant-1")
        #expect(items[markerIndex!].unreadMarker?.unreadCount == 2)
        #expect(items.filter { $0.timelineItem != nil }.map(\.id) == timeline.map(\.id))
    }

    @Test func adapterSkipsUnreadMarkerWhenBoundaryIsMissingOrEmpty() {
        let messages = sampleMessages()
        let timeline = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: Date(timeIntervalSince1970: 200))

        let missing = AgentChatTimelineAdapter().items(
            from: timeline,
            unreadBoundary: CommercialChatUnreadBoundary(beforeItemID: "missing", unreadCount: 2)
        )
        let empty = AgentChatTimelineAdapter().items(
            from: timeline,
            unreadBoundary: CommercialChatUnreadBoundary(beforeItemID: "assistant-1", unreadCount: 0)
        )

        #expect(missing.map(\.id) == timeline.map(\.id))
        #expect(empty.map(\.id) == timeline.map(\.id))
    }

    private func sampleMessages() -> [AgentMessage] {
        [
            AgentMessage(id: "user-1", role: .user, content: "你好", createdAt: Date(timeIntervalSince1970: 100)),
            AgentMessage(id: "assistant-1", role: .assistant, content: "你好，我是康纳同学。", createdAt: Date(timeIntervalSince1970: 101))
        ]
    }
}
