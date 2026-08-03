import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
@Suite("IM attention coordinator")
struct ImAttentionCoordinatorTests {
    @Test func systemNotificationRequiresSystemLevelSetting() {
        var delivered: [ImSystemNotification] = []
        let coordinator = ImAttentionCoordinator(deliver: { delivered.append($0) })
        coordinator.canUseUserNotifications = { true }
        let event = incomingMessageEvent()

        for level in [SessionAttentionLevel.none, .unread, .emphasized] {
            coordinator.notificationSettings = { (true, level) }
            coordinator.handle(event)
        }
        #expect(delivered.isEmpty)

        coordinator.notificationSettings = { (true, .actionable) }
        coordinator.handle(event)
        #expect(delivered.count == 1)
        #expect(delivered.first?.userInfo["imConversationID"] == "peer:9")
    }

    @Test func visibleOrMutedConversationSuppressesNotification() {
        var delivered: [ImSystemNotification] = []
        let coordinator = ImAttentionCoordinator(deliver: { delivered.append($0) })
        coordinator.canUseUserNotifications = { true }
        coordinator.notificationSettings = { (true, .interruptive) }
        coordinator.isConversationVisible = { $0 == "peer:9" }
        coordinator.handle(incomingMessageEvent())

        coordinator.isConversationVisible = { _ in false }
        coordinator.handle(incomingMessageEvent(muted: true))
        #expect(delivered.isEmpty)
    }

    @Test func friendInvitationUsesSettingsAndOpensContacts() {
        var delivered: [ImSystemNotification] = []
        let coordinator = ImAttentionCoordinator(deliver: { delivered.append($0) })
        coordinator.canUseUserNotifications = { true }
        coordinator.notificationSettings = { (true, .interruptive) }
        coordinator.handle(.incomingFriendRequest(ImFriendRequest(
            id: 5,
            senderId: 9,
            receiverId: 1,
            senderUsername: "alice",
            senderNickname: "爱丽丝"
        )))

        #expect(delivered.count == 1)
        #expect(delivered.first?.title == "新的康纳好友邀请")
        #expect(delivered.first?.body == "爱丽丝 请求添加你为好友")
        #expect(delivered.first?.userInfo["openContacts"] == "true")
        #expect(delivered.first?.interruptionLevel == .timeSensitive)
    }

    private func incomingMessageEvent(muted: Bool = false) -> ImRealtimeEvent {
        .incomingMessage(
            message: ImMessage(
                id: "m1",
                conversationId: "peer:9",
                senderId: 9,
                senderName: "爱丽丝",
                content: "你好",
                status: .delivered,
                createdAt: 1
            ),
            conversation: ImConversation(
                id: "peer:9",
                kind: .peer,
                peerUserId: 9,
                title: "爱丽丝",
                muted: muted
            )
        )
    }
}
