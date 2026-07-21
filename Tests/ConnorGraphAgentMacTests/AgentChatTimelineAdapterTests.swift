import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Agent Chat Timeline Adapter Tests")
struct AgentChatTimelineAdapterTests {
    @MainActor
    @Test func assistantHeaderUsesWebsiteBrandMessage() {
        let header = AgentAssistantHeaderView()

        #expect(header.displayName == "康纳同学")
        #expect(header.subtitle == "一个拥有记忆、可以自我进化的 Agent")
        #expect(header.slogan == "从共同经验中学习，并把知识直接用于真实任务。")
    }

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

    @Test func adapterInsertsDateSeparatorsForDistinctDays() {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 25, hour: 20, calendar: calendar)
        let messages = [
            AgentMessage(id: "user-1", role: .user, content: "昨天的问题", createdAt: date(year: 2026, month: 6, day: 24, hour: 10, calendar: calendar)),
            AgentMessage(id: "assistant-1", role: .assistant, content: "昨天的回答", createdAt: date(year: 2026, month: 6, day: 24, hour: 10, minute: 1, calendar: calendar)),
            AgentMessage(id: "user-2", role: .user, content: "今天的问题", createdAt: date(year: 2026, month: 6, day: 25, hour: 9, calendar: calendar))
        ]
        let timeline = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: now, calendar: calendar)

        let items = AgentChatTimelineAdapter().items(from: timeline, insertsDateSeparators: true, now: now, calendar: calendar)
        let separators = items.compactMap(\.dateSeparator)

        #expect(separators.map(\.dayIdentifier) == ["2026-06-24", "2026-06-25"])
        #expect(separators.map(\.title) == ["昨天", "今天"])
        #expect(items.first?.kind == .dateSeparator)
        #expect(items.filter { $0.timelineItem != nil }.map(\.id) == timeline.map(\.id))
    }

    @Test func adapterDoesNotDuplicateDateSeparatorsWithinSameDay() {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 25, hour: 20, calendar: calendar)
        let timeline = AgentChatTurnTimelineItem.items(messages: sampleMessages(), lastContext: nil, isSubmitting: false, now: now, calendar: calendar)

        let items = AgentChatTimelineAdapter().items(from: timeline, insertsDateSeparators: true, now: now, calendar: calendar)

        #expect(items.filter { $0.kind == .dateSeparator }.count == 1)
    }

    @Test func adapterCombinesUnreadMarkerWithDateSeparatorsWithoutChangingTimelineOrder() {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 25, hour: 20, calendar: calendar)
        let timeline = AgentChatTurnTimelineItem.items(messages: sampleMessages(), lastContext: nil, isSubmitting: false, now: now, calendar: calendar)

        let items = AgentChatTimelineAdapter().items(
            from: timeline,
            unreadBoundary: CommercialChatUnreadBoundary(beforeItemID: "assistant-1", unreadCount: 1),
            insertsDateSeparators: true,
            now: now,
            calendar: calendar
        )

        #expect(items.contains { $0.kind == .dateSeparator })
        #expect(items.contains { $0.kind == .unreadSeparator })
        #expect(items.filter { $0.timelineItem != nil }.map(\.id) == timeline.map(\.id))
    }

    @Test func prependAnchorUsesStableMessageInsteadOfLeadingDecorations() {
        let calendar = fixedCalendar()
        let now = date(year: 2026, month: 6, day: 25, hour: 20, calendar: calendar)
        let timeline = AgentChatTurnTimelineItem.items(
            messages: sampleMessages(),
            lastContext: nil,
            isSubmitting: false,
            now: now,
            calendar: calendar
        )
        let items = AgentChatTimelineAdapter().items(
            from: timeline,
            insertsDateSeparators: true,
            now: now,
            calendar: calendar
        )

        #expect(items.first?.kind == .dateSeparator)
        #expect(AgentChatTimelineAdapter().prependAnchorItemID(in: items) == "user-1")
    }

    private func sampleMessages() -> [AgentMessage] {
        [
            AgentMessage(id: "user-1", role: .user, content: "你好", createdAt: Date(timeIntervalSince1970: 100)),
            AgentMessage(id: "assistant-1", role: .assistant, content: "你好，我是康纳同学。", createdAt: Date(timeIntervalSince1970: 101))
        ]
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
