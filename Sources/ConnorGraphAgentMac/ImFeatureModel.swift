import Foundation
import Combine
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

/// Lock-protected snapshot of the signed-in IM identity: `ImMessageCenter` pulls
/// the current identity through a synchronous `@Sendable` closure, which cannot
/// hop to the main actor where `AppUserIdentityStore` lives.
final class ImSelfIdentityBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: ImSelfIdentity?

    var value: ImSelfIdentity? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// UI-facing IM state slice, ported from the Android `ConnorViewModel` IM fields:
/// conversation list, opened-conversation messages, contacts (friends / requests /
/// user search), multi-select and the anonymized forward-to-AI flow. All persistent
/// state lives in `SQLiteImStore`; this model re-reads on store change notifications
/// exactly like Android collects Room flows.
@MainActor
@Observable
final class ImFeatureModel {
    // MARK: - Store-backed state

    private(set) var conversations: [ImConversation] = []
    private(set) var messages: [ImMessage] = []
    private(set) var friends: [ImFriend] = []
    private(set) var friendRequests: [ImFriendRequest] = []
    private(set) var selectedConversationId: String?
    private(set) var socketConnected = false
    private(set) var isSignedIn = false
    private(set) var selfUserId: Int64?

    // MARK: - Contacts screen transient state

    private(set) var userSearchResults: [ImPublicUserDTO] = []
    var contactMessage: String?

    // MARK: - Multi-select + forward-to-AI

    private(set) var selectedMessageIds: Set<String> = []
    private(set) var isSelectionMode = false
    var isForwardSheetPresented = false
    var forwardCaption = ""
    private(set) var isForwarding = false
    /// Whether older history may remain before the oldest cached message.
    private(set) var hasOlderMessages = true
    var errorMessage: String?

    var selectedConversation: ImConversation? {
        guard let selectedConversationId else { return nil }
        return conversations.first { $0.id == selectedConversationId }
    }

    /// Android parity: pinned first, then most recent activity.
    var sortedConversations: [ImConversation] {
        conversations.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            let lhsAt = max(lhs.lastMessageAt, lhs.updatedAt)
            let rhsAt = max(rhs.lastMessageAt, rhs.updatedAt)
            return lhsAt > rhsAt
        }
    }

    var totalUnreadCount: Int {
        conversations.filter { !$0.muted }.reduce(0) { $0 + $1.unreadCount }
    }

    var pendingIncomingRequestCount: Int {
        guard let selfUserId else { return 0 }
        return friendRequests.filter { $0.receiverId == selfUserId && $0.status == "pending" }.count
    }

    // MARK: - Dependencies

    @ObservationIgnored private let store: SQLiteImStore
    @ObservationIgnored private let center: ImMessageCenter
    @ObservationIgnored private let identityStore: AppUserIdentityStore
    /// Auto-creates/reuses a 人际关系 person profile for every Connor friend.
    @ObservationIgnored private let friendProvisioner: ImFriendPersonProvisioner?
    /// Live Memory OS facade (rebuilt at runtime, hence a closure).
    @ObservationIgnored private let forwardFacade: @MainActor () -> AppMemoryOSFacade?
    /// Submit into a brand-new AI session; returns the created session id.
    @ObservationIgnored private let forwardToNewSession: @MainActor (String) async -> String?
    /// Submit into an existing AI session (selecting it first); returns the session id.
    @ObservationIgnored private let forwardToExistingSession: @MainActor (String, String) async -> String?

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(
        store: SQLiteImStore,
        center: ImMessageCenter,
        identityStore: AppUserIdentityStore,
        friendProvisioner: ImFriendPersonProvisioner? = nil,
        forwardFacade: @escaping @MainActor () -> AppMemoryOSFacade?,
        forwardToNewSession: @escaping @MainActor (String) async -> String?,
        forwardToExistingSession: @escaping @MainActor (String, String) async -> String?
    ) {
        self.store = store
        self.center = center
        self.identityStore = identityStore
        self.friendProvisioner = friendProvisioner
        self.forwardFacade = forwardFacade
        self.forwardToNewSession = forwardToNewSession
        self.forwardToExistingSession = forwardToExistingSession
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        storeObserver = NotificationCenter.default.addObserver(
            forName: .connorImStoreDidChange,
            object: store,
            queue: .main
        ) { [weak self] notification in
            let scope = notification.userInfo?[ImStoreChangeNotificationUserInfoKey.scope] as? String
            let conversationID = notification.userInfo?[ImStoreChangeNotificationUserInfoKey.conversationID] as? String
            Task { @MainActor [weak self] in
                await self?.reload(scopeRawValue: scope, conversationID: conversationID)
            }
        }

        identityStore.$isImSocketConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.socketConnected = connected
            }
            .store(in: &cancellables)

        identityStore.$authenticationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .signedIn(let user):
                    self.isSignedIn = true
                    self.selfUserId = Int64(user.id)
                case .signedOut, .expired:
                    let wasSignedIn = self.isSignedIn
                    self.isSignedIn = false
                    self.selfUserId = nil
                    if wasSignedIn {
                        Task { [weak self] in await self?.handleSignOut() }
                    }
                case .restoring:
                    break
                }
            }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self else { return }
            await self.center.prepareAfterLaunch()
            await self.reloadAll()
        }
    }

    func shutdown() {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        cancellables.removeAll()
    }

    private func handleSignOut() async {
        await center.handleSignOut()
        selectedConversationId = nil
        await center.setActiveConversation(nil)
        messages = []
        userSearchResults = []
        contactMessage = nil
        clearSelection()
        isForwardSheetPresented = false
    }

    // MARK: - Store reload

    private func reload(scopeRawValue: String?, conversationID: String?) async {
        guard let scopeRawValue, let scope = ImStoreChangeScope(rawValue: scopeRawValue) else {
            await reloadAll()
            return
        }
        switch scope {
        case .conversations:
            conversations = (try? await store.loadConversations()) ?? []
        case .messages:
            conversations = (try? await store.loadConversations()) ?? []
            if let selectedConversationId, conversationID == nil || conversationID == selectedConversationId {
                messages = (try? await store.messages(conversationId: selectedConversationId)) ?? []
            }
        case .friends:
            friends = (try? await store.loadFriends()) ?? []
            await reconcileFriendProfiles()
        case .friendRequests:
            friendRequests = (try? await store.loadFriendRequests()) ?? []
        case .forwardAliases:
            break
        }
    }

    private func reloadAll() async {
        conversations = (try? await store.loadConversations()) ?? []
        friends = (try? await store.loadFriends()) ?? []
        friendRequests = (try? await store.loadFriendRequests()) ?? []
        await reconcileFriendProfiles()
        if let selectedConversationId {
            messages = (try? await store.messages(conversationId: selectedConversationId)) ?? []
        } else {
            messages = []
        }
    }

    // MARK: - Conversations (Android `selectImConversation` semantics)

    func selectConversation(_ id: String?) async {
        clearSelection()
        selectedConversationId = id
        hasOlderMessages = true
        await center.setActiveConversation(id)
        guard let id else {
            messages = []
            return
        }
        messages = (try? await store.messages(conversationId: id)) ?? []
        await center.markConversationRead(id)
        if messages.isEmpty {
            await loadOlderMessages()
        }
    }

    func sendMessage(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let conversation = selectedConversation else { return }
        do {
            switch conversation.kind {
            case .peer:
                guard let peerId = conversation.peerUserId else { return }
                try await center.sendChatMessage(peerId: peerId, content: content)
            case .group:
                guard let groupId = conversation.groupId else { return }
                try await center.sendGroupMessage(groupId: groupId, content: content)
            }
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    func retryMessage(_ messageId: String) async {
        do {
            try await center.retryMessage(messageId: messageId)
        } catch {
            errorMessage = "重发失败：\(error.localizedDescription)"
        }
    }

    func loadOlderMessages() async {
        guard let selectedConversationId else { return }
        hasOlderMessages = (try? await center.loadOlderMessages(conversationId: selectedConversationId, limit: 20)) ?? false
    }

    func setPinned(conversationId: String, pinned: Bool) async {
        try? await center.setPinned(conversationId: conversationId, pinned: pinned)
    }

    func setMuted(conversationId: String, muted: Bool) async {
        try? await center.setMuted(conversationId: conversationId, muted: muted)
    }

    func deleteConversation(_ conversationId: String) async {
        try? await center.deleteConversation(conversationId)
        if selectedConversationId == conversationId {
            await selectConversation(nil)
        }
    }

    // MARK: - Contacts (friends / requests / search)

    func refreshContacts() async {
        await center.refreshAll()
        friends = (try? await store.loadFriends()) ?? []
        await reconcileFriendProfiles()
    }

    /// Contact-list "发消息": ensure the peer conversation exists, then open it.
    func openPeerConversation(peerId: Int64) async {
        do {
            let conversationId = try await center.openPeerConversation(peerId: peerId)
            conversations = (try? await store.loadConversations()) ?? []
            await selectConversation(conversationId)
        } catch {
            errorMessage = "打开会话失败：\(error.localizedDescription)"
        }
    }

    func searchUsers(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            userSearchResults = []
            return
        }
        do {
            userSearchResults = try await center.searchUsers(query: trimmed, limit: 10)
        } catch {
            userSearchResults = []
            contactMessage = "搜索失败：\(error.localizedDescription)"
        }
    }

    func clearUserSearch() {
        userSearchResults = []
    }

    func sendFriendRequest(username: String, message: String = "") async {
        do {
            try await center.sendFriendRequest(username: username, message: message)
            contactMessage = "好友请求已发送"
        } catch {
            contactMessage = "发送好友请求失败：\(error.localizedDescription)"
        }
    }

    func acceptFriendRequest(requestId: Int64) async {
        do {
            try await center.acceptFriendRequest(requestId: requestId)
            friends = (try? await store.loadFriends()) ?? []
            await reconcileFriendProfiles()
            contactMessage = "已同意好友请求"
        } catch {
            contactMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    func rejectFriendRequest(requestId: Int64) async {
        do {
            try await center.rejectFriendRequest(requestId: requestId)
            contactMessage = "已拒绝好友请求"
        } catch {
            contactMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    func removeFriend(userId: Int64) async {
        do {
            try await center.removeFriend(userId: userId)
            friends = (try? await store.loadFriends()) ?? []
            contactMessage = "已删除好友"
        } catch {
            contactMessage = "删除好友失败：\(error.localizedDescription)"
        }
    }

    /// Friend ↔ local person profile binding (nil unbinds), the anonymization bridge.
    func bindFriendPerson(userId: Int64, personProfileID: String?) async {
        do {
            try await center.bindFriendPerson(userId: userId, personProfileID: personProfileID)
            friends = (try? await store.loadFriends()) ?? friends
            contactMessage = personProfileID == nil ? "已解除人物关联" : "已关联人物"
        } catch {
            contactMessage = "关联人物失败：\(error.localizedDescription)"
        }
    }

    /// Auto-provisions person profiles for unbound friends. Creating a profile
    /// posts the person-profile store change notification, which refreshes the
    /// 人际关系 feature model automatically.
    private func reconcileFriendProfiles() async {
        guard let friendProvisioner, !friends.isEmpty else { return }
        do {
            _ = try await friendProvisioner.reconcile(friends: friends)
            friends = (try? await store.loadFriends()) ?? friends
        } catch {
            contactMessage = "同步好友人物档案失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Multi-select (Android `imSelectionMode` semantics)

    func enterSelectionMode(initialMessageId: String) {
        isSelectionMode = true
        selectedMessageIds = [initialMessageId]
    }

    func toggleMessageSelection(_ messageId: String) {
        if selectedMessageIds.contains(messageId) {
            selectedMessageIds.remove(messageId)
        } else {
            selectedMessageIds.insert(messageId)
        }
        if selectedMessageIds.isEmpty {
            isSelectionMode = false
        }
    }

    func clearSelection() {
        selectedMessageIds = []
        isSelectionMode = false
    }

    // MARK: - Forward to AI (anonymize → ingest → compose → submit)

    /// Android `forwardSelectedImMessages` tail: anonymize the selection, ingest the
    /// transcript into Memory OS (idempotent per batch), compose caption + disclaimer
    /// + transcript, then submit into the target AI session (or a new one).
    /// Returns the target session id on success.
    @discardableResult
    func forwardSelectedMessages(targetSessionId: String?) async -> String? {
        guard !isForwarding,
              let conversation = selectedConversation,
              !selectedMessageIds.isEmpty
        else { return nil }
        guard let selfId = await center.selfUserId() else {
            errorMessage = "请先登录后再转发"
            return nil
        }
        isForwarding = true
        defer { isForwarding = false }

        let selected = messages.filter { selectedMessageIds.contains($0.id) }
        guard !selected.isEmpty else { return nil }

        do {
            let store = self.store
            let anonymizer = ImTranscriptAnonymizer(store: store)
            let forward = try await anonymizer.anonymize(
                messages: selected,
                conversation: conversation,
                selfUserId: selfId,
                friendLookup: { senderId in
                    // Bound friends only: unbound senders degrade to ephemeral tokens.
                    guard let friend = try? await store.friend(userId: senderId),
                          let personProfileID = friend.personProfileID
                    else { return nil }
                    return ImParticipantInfo(personProfileID: personProfileID, displayName: friend.displayName)
                }
            )

            let batchID = ImForwardComposer.batchID(conversationId: conversation.id, messageIds: selected.map(\.id))
            if let facade = forwardFacade() {
                let ingestor = ImForwardTranscriptIngestor(facade: facade)
                try ingestor.ingest(batchID: batchID, transcriptText: forward.transcriptText)
            }

            let composed = ImForwardComposer.composeMessage(caption: forwardCaption, transcriptText: forward.transcriptText)
            let sessionId: String?
            if let targetSessionId {
                sessionId = await forwardToExistingSession(targetSessionId, composed)
            } else {
                sessionId = await forwardToNewSession(composed)
            }
            guard let sessionId else {
                errorMessage = "转发失败"
                return nil
            }

            // Android parity: leave the IM chat and land on the AI session.
            forwardCaption = ""
            isForwardSheetPresented = false
            clearSelection()
            await selectConversation(nil)
            return sessionId
        } catch {
            errorMessage = "转发失败：\(error.localizedDescription)"
            return nil
        }
    }
}
