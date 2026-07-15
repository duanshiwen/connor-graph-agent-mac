import AppKit
import Foundation
import Observation
import UserNotifications
import ConnorGraphAgent
import ConnorGraphAppSupport

private actor SessionReadStatePersistenceCoordinator {
    private var latestRevisionBySessionID: [String: UInt64] = [:]

    func persist(
        _ state: SessionReadState,
        sessionID: String,
        revision: UInt64,
        repository: AppChatSessionRepository
    ) -> String? {
        guard revision > latestRevisionBySessionID[sessionID, default: 0] else { return nil }
        latestRevisionBySessionID[sessionID] = revision
        do {
            try repository.persistReadState(sessionID: sessionID, readState: state)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

@MainActor
@Observable
final class ChatAttentionCoordinator {
    private let model: ChatSessionListModel
    private let repository: AppChatSessionRepository?
    private var lastNotificationAt: [String: Date] = [:]
    private let sameSessionNotificationCooldown: TimeInterval
    @ObservationIgnored private let persistenceCoordinator = SessionReadStatePersistenceCoordinator()
    @ObservationIgnored private var persistenceRevision: UInt64 = 0

    @ObservationIgnored var selectedNavigation: () -> SidebarItem = { .agentChat }
    @ObservationIgnored var notificationSettings: () -> (enabled: Bool, level: SessionAttentionLevel) = { (false, .none) }
    @ObservationIgnored var latestSelectedMessageID: () -> String? = { nil }
    @ObservationIgnored var canUseUserNotifications: () -> Bool = { false }
    @ObservationIgnored var onLoadedReadStateChanged: (String, SessionReadState) -> Void = { _, _ in }
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(
        model: ChatSessionListModel,
        repository: AppChatSessionRepository?,
        sameSessionNotificationCooldown: TimeInterval = 300
    ) {
        self.model = model
        self.repository = repository
        self.sameSessionNotificationCooldown = sameSessionNotificationCooldown
    }

    func synchronize(from sessions: [AgentSession]) {
        model.readStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.readState) })
        refreshDockBadge()
    }

    func install(_ session: AgentSession) {
        model.readStates[session.id] = session.readState
        refreshDockBadge()
    }

    func shouldTreatUpdateAsRead(sessionID: String) -> Bool {
        selectedNavigation() == .agentChat && model.selectedSessionID == sessionID
    }

    func markRead(_ sessionID: String) {
        guard model.readStates[sessionID]?.highestLevel != SessionAttentionLevel.none || model.readStates[sessionID]?.unreadCount ?? 0 > 0 else { return }
        var state = model.readStates[sessionID] ?? .initial()
        state.markRead(messageID: latestMessageID(for: sessionID), at: Date())
        apply(state, sessionID: sessionID, persist: true)
    }

    func noteUpdate(sessionID: String, messageID: String?, preview: String?, notificationBody: String) {
        let settings = notificationSettings()
        if shouldTreatUpdateAsRead(sessionID: sessionID) {
            var state = model.readStates[sessionID] ?? .initial()
            state.markRead(messageID: messageID ?? latestMessageID(for: sessionID), at: Date())
            apply(state, sessionID: sessionID, persist: true)
            return
        }
        let unreadMessageID = messageID ?? "attention-event-\(UUID().uuidString)"
        var state = model.readStates[sessionID] ?? .initial()
        state.markUnread(messageID: unreadMessageID, preview: preview, level: settings.level, at: Date())
        apply(state, sessionID: sessionID, persist: true)
        postNotificationIfNeeded(sessionID: sessionID, body: notificationBody, level: settings.level, enabled: settings.enabled)
    }

    private func latestMessageID(for sessionID: String) -> String? {
        if model.selectedSessionID == sessionID, let selected = latestSelectedMessageID() { return selected }
        return model.sessions.first(where: { $0.id == sessionID })?.messages.last?.id
            ?? model.allSessions.first(where: { $0.id == sessionID })?.messages.last?.id
    }

    private func apply(_ state: SessionReadState, sessionID: String, persist: Bool) {
        model.readStates[sessionID] = state
        updateLoadedSession(sessionID: sessionID, state: state)
        if persist { persistReadState(state, sessionID: sessionID) }
        refreshDockBadge()
    }

    private func updateLoadedSession(sessionID: String, state: SessionReadState) {
        if let index = model.sessions.firstIndex(where: { $0.id == sessionID }) {
            model.sessions[index].readState = state
        }
        if let index = model.allSessions.firstIndex(where: { $0.id == sessionID }) {
            model.allSessions[index].readState = state
        }
        onLoadedReadStateChanged(sessionID, state)
    }

    private func persistReadState(_ state: SessionReadState, sessionID: String) {
        guard let repository else { return }
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let persistenceCoordinator = persistenceCoordinator
        Task { [weak self] in
            guard let message = await persistenceCoordinator.persist(
                state,
                sessionID: sessionID,
                revision: revision,
                repository: repository
            ) else { return }
            self?.onError(message)
        }
    }

    private func postNotificationIfNeeded(sessionID: String, body: String, level: SessionAttentionLevel, enabled: Bool) {
        guard enabled, canUseUserNotifications(), level.shouldRequestSystemNotification else { return }
        guard !shouldTreatUpdateAsRead(sessionID: sessionID) else { return }
        let now = Date()
        if let last = lastNotificationAt[sessionID], now.timeIntervalSince(last) < sameSessionNotificationCooldown { return }
        lastNotificationAt[sessionID] = now
        let content = UNMutableNotificationContent()
        content.title = "康纳同学：主人，有新消息需要你关注"
        content.body = body
        content.sound = .default
        if level == .interruptive {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        content.userInfo = [
            "sessionID": sessionID,
            "attentionLevel": level.rawValue,
            "bundlePath": Bundle.main.bundlePath
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "session-\(sessionID)-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    func refreshDockBadge(application: NSApplication? = NSApp) {
        let count = model.readStates.values.reduce(0) { partial, state in
            guard state.highestLevel.shouldCountInDockBadge else { return partial }
            return partial + max(state.unreadCount, 1)
        }
        Self.applyDockBadge(count: count, application: application)
    }

    static func applyDockBadge(count: Int, application: NSApplication?) {
        guard let application else { return }
        application.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
