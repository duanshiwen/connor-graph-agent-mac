import Foundation
import UserNotifications
import ConnorGraphAppSupport
import ConnorGraphCore

struct ImSystemNotification: Equatable {
    var identifierPrefix: String
    var title: String
    var body: String
    var interruptionLevel: UNNotificationInterruptionLevel
    var userInfo: [String: String]
}

@MainActor
final class ImAttentionCoordinator {
    private var lastNotificationAt: [String: Date] = [:]
    private let sameSourceNotificationCooldown: TimeInterval
    private let now: () -> Date
    private let deliver: (ImSystemNotification) -> Void

    var notificationSettings: () -> (enabled: Bool, level: SessionAttentionLevel) = { (false, .none) }
    var isConversationVisible: (String) -> Bool = { _ in false }
    var isContactsVisible: () -> Bool = { false }
    var canUseUserNotifications: () -> Bool = { false }

    init(
        sameSourceNotificationCooldown: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.sameSourceNotificationCooldown = sameSourceNotificationCooldown
        self.now = now
        self.deliver = { notification in
            ImAttentionCoordinator.deliverSystemNotification(notification)
        }
    }

    init(
        sameSourceNotificationCooldown: TimeInterval = 300,
        now: @escaping () -> Date = Date.init,
        deliver: @escaping (ImSystemNotification) -> Void
    ) {
        self.sameSourceNotificationCooldown = sameSourceNotificationCooldown
        self.now = now
        self.deliver = deliver
    }

    func handle(_ event: ImRealtimeEvent) {
        let settings = notificationSettings()
        guard settings.enabled,
              settings.level.shouldRequestSystemNotification,
              canUseUserNotifications()
        else { return }

        switch event {
        case .incomingMessage(let message, let conversation):
            guard !conversation.muted, !isConversationVisible(conversation.id) else { return }
            post(
                sourceKey: "im-conversation:\(conversation.id)",
                notification: ImSystemNotification(
                    identifierPrefix: "im-message-\(conversation.id)",
                    title: "\(message.senderName.isEmpty ? conversation.participantName : message.senderName) 发来新消息",
                    body: Self.preview(message.content, fallback: "收到一条新消息"),
                    interruptionLevel: settings.level == .interruptive ? .timeSensitive : .active,
                    userInfo: [
                        "imConversationID": conversation.id,
                        "attentionLevel": String(settings.level.rawValue),
                        "bundlePath": Bundle.main.bundlePath
                    ]
                )
            )
        case .incomingFriendRequest(let request):
            guard !isContactsVisible() else { return }
            let displayName = request.senderNickname.isEmpty ? request.senderUsername : request.senderNickname
            post(
                sourceKey: "im-friend-request",
                notification: ImSystemNotification(
                    identifierPrefix: "im-friend-request",
                    title: "新的康纳好友邀请",
                    body: displayName.isEmpty ? "收到一条新的好友邀请" : "\(displayName) 请求添加你为好友",
                    interruptionLevel: settings.level == .interruptive ? .timeSensitive : .active,
                    userInfo: [
                        "openContacts": "true",
                        "attentionLevel": String(settings.level.rawValue),
                        "bundlePath": Bundle.main.bundlePath
                    ]
                )
            )
        }
    }

    private func post(sourceKey: String, notification: ImSystemNotification) {
        let current = now()
        if let last = lastNotificationAt[sourceKey], current.timeIntervalSince(last) < sameSourceNotificationCooldown {
            return
        }
        lastNotificationAt[sourceKey] = current
        deliver(notification)
    }

    private static func preview(_ content: String, fallback: String) -> String {
        let collapsed = content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return fallback }
        guard collapsed.count > 140 else { return collapsed }
        return String(collapsed.prefix(140)) + "…"
    }

    private static func deliverSystemNotification(_ notification: ImSystemNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = notification.interruptionLevel
        if notification.interruptionLevel == .timeSensitive { content.relevanceScore = 1.0 }
        content.userInfo = notification.userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(notification.identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }
}
