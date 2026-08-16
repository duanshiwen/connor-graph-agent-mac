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
    private(set) var selfAvatarURL = ""
    private(set) var selfAvatarRevision: UInt = 0
    private(set) var participantMessagesByConversation: [String: [ImMessage]] = [:]
    private(set) var regeneratingTitleConversationIDs: Set<String> = []

    // MARK: - Contacts screen transient state

    private(set) var userSearchResults: [ImPublicUserDTO] = []
    /// 搜索进行中：加好友弹窗据此显示加载态。
    private(set) var isSearchingUsers = false
    /// 正在发送好友申请的用户名集合：行内按钮据此显示提交态。
    private(set) var friendRequestSubmittingUsernames: Set<String> = []
    var contactMessage: String?

    // MARK: - Multi-select + forward-to-AI

    private(set) var selectedMessageIds: Set<String> = []
    private(set) var isSelectionMode = false
    var isForwardSheetPresented = false
    var forwardCaption = ""
    private(set) var isForwarding = false
    /// Whether older history may remain before the oldest cached message.
    private(set) var hasOlderMessages = true
    private(set) var isSendingMedia = false
    private(set) var selectedGroupDetail: ImGroupDTO?
    private(set) var selectedGroupMembers: [ImGroupMemberDTO] = []
    private(set) var isLoadingGroupDetails = false
    var errorMessage: String?

    var selectedConversation: ImConversation? {
        guard let selectedConversationId else { return nil }
        return conversations.first { $0.id == selectedConversationId }
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
    @ObservationIgnored private let generateTitle: @MainActor ([ImMessage], String) async throws -> String
    /// 转发目标分页加载器工厂（由组合根注入；nil 时回退为空列表）。
    @ObservationIgnored private let makeForwardPager: @MainActor () -> ForwardDestinationPager?

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
        forwardToExistingSession: @escaping @MainActor (String, String) async -> String?,
        generateTitle: @escaping @MainActor ([ImMessage], String) async throws -> String,
        makeForwardPager: @escaping @MainActor () -> ForwardDestinationPager? = { nil }
    ) {
        self.store = store
        self.center = center
        self.identityStore = identityStore
        self.friendProvisioner = friendProvisioner
        self.forwardFacade = forwardFacade
        self.forwardToNewSession = forwardToNewSession
        self.forwardToExistingSession = forwardToExistingSession
        self.generateTitle = generateTitle
        self.makeForwardPager = makeForwardPager
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
                    let nextUserId = Int64(user.id)
                    if let previousUserId = self.selfUserId, previousUserId != nextUserId {
                        Task { [weak self] in await self?.handleSignOut() }
                    }
                    self.isSignedIn = true
                    self.selfUserId = nextUserId
                    self.selfAvatarURL = user.avatarURL ?? ""
                case .signedOut, .expired:
                    let wasSignedIn = self.isSignedIn
                    self.isSignedIn = false
                    self.selfUserId = nil
                    self.selfAvatarURL = ""
                    if wasSignedIn {
                        Task { [weak self] in await self?.handleSignOut() }
                    }
                case .restoring:
                    break
                }
            }
            .store(in: &cancellables)

        identityStore.$avatarRevision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] revision in
                self?.selfAvatarRevision = revision
            }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self else { return }
            await self.center.prepareAfterLaunch()
            await self.center.refreshAll()
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
        selectedGroupDetail = nil
        selectedGroupMembers = []
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
            await reloadParticipantMessages()
        case .messages:
            conversations = (try? await store.loadConversations()) ?? []
            await reloadParticipantMessages()
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

    /// 账号切换后（底层 IM 库已指向新账号）重新读取全部状态。
    func reloadAfterAccountSwitch() async {
        await reloadAll()
    }

    private func reloadAll() async {
        conversations = (try? await store.loadConversations()) ?? []
        await reloadParticipantMessages()
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

        let cachedMessages = (try? await store.messages(conversationId: id)) ?? []
        messages = cachedMessages
        hasOlderMessages = (try? await center.reconcileLatestMessages(conversationId: id, limit: 50)) ?? true
        guard selectedConversationId == id else { return }
        messages = (try? await store.messages(conversationId: id)) ?? cachedMessages
        await center.markConversationRead(id)
    }

    func searchConversations(query: String, limit: Int) async throws -> [ImConversationSearchHit] {
        try await store.searchConversations(query: query, limit: limit)
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

    func sendMedia(fileURL: URL, messageType: ImMessageType, metadata: ImMediaMetadata) async {
        guard let conversation = selectedConversation, !isSendingMedia else { return }
        isSendingMedia = true
        defer { isSendingMedia = false }
        do {
            try await center.sendMediaMessage(
                conversationId: conversation.id,
                fileURL: fileURL,
                messageType: messageType,
                metadata: metadata
            )
        } catch {
            errorMessage = "媒体发送失败：\(error.localizedDescription)"
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

    func setMuted(conversationId: String, muted: Bool) async {
        try? await center.setMuted(conversationId: conversationId, muted: muted)
    }

    func renameConversation(conversationId: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await center.renameConversation(conversationId: conversationId, title: trimmed)
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
        }
    }

    func setStatus(conversationId: String, status: AgentSessionStatus) async {
        do {
            try await center.setConversationStatus(conversationId: conversationId, status: status)
        } catch {
            errorMessage = "更新状态失败：\(error.localizedDescription)"
        }
    }

    func toggleLabel(conversationId: String, labelId: String) async {
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return }
        var labels = conversation.labelIds
        if let index = labels.firstIndex(of: labelId) {
            labels.remove(at: index)
        } else {
            labels.append(labelId)
        }
        do {
            try await center.setConversationLabels(conversationId: conversationId, labelIds: labels)
        } catch {
            errorMessage = "更新标签失败：\(error.localizedDescription)"
        }
    }

    func regenerateTitle(conversationId: String) async {
        guard !regeneratingTitleConversationIDs.contains(conversationId) else { return }
        let latestMessages = ((try? await store.messages(conversationId: conversationId)) ?? []).suffix(10)
        guard !latestMessages.isEmpty else {
            errorMessage = "至少需要一条消息才能生成标题"
            return
        }
        regeneratingTitleConversationIDs.insert(conversationId)
        defer { regeneratingTitleConversationIDs.remove(conversationId) }
        do {
            let title = try await generateTitle(Array(latestMessages), conversationId)
            try await center.renameConversation(conversationId: conversationId, title: title)
        } catch {
            errorMessage = "生成标题失败：\(error.localizedDescription)"
        }
    }

    func deleteConversation(_ conversationId: String) async {
        try? await center.deleteConversation(conversationId)
        if selectedConversationId == conversationId {
            await selectConversation(nil)
        }
    }

    func participantMessages(for conversationId: String) -> [ImMessage] {
        participantMessagesByConversation[conversationId] ?? []
    }

    // MARK: - Normal groups

    @discardableResult
    func createGroup(name: String, description: String, memberIds: [Int64]) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        do {
            let group = try await center.createGroup(
                name: trimmedName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                memberIds: memberIds
            )
            conversations = (try? await store.loadConversations()) ?? []
            await selectConversation(ImConversation.groupConversationID(groupId: group.groupId))
            return true
        } catch {
            errorMessage = "创建群聊失败：\(error.localizedDescription)"
            return false
        }
    }

    func loadSelectedGroupDetails() async {
        guard let groupId = selectedConversation?.groupId else { return }
        isLoadingGroupDetails = true
        defer { isLoadingGroupDetails = false }
        do {
            async let detail = center.groupDetail(groupId: groupId)
            async let members = center.groupMembers(groupId: groupId)
            selectedGroupDetail = try await detail
            selectedGroupMembers = try await members
        } catch {
            selectedGroupDetail = nil
            selectedGroupMembers = []
            errorMessage = "加载群聊详情失败：\(error.localizedDescription)"
        }
    }

    func inviteGroupMember(userId: Int64) async {
        guard let groupId = selectedConversation?.groupId else { return }
        do {
            try await center.inviteGroupMember(groupId: groupId, userId: userId)
            await loadSelectedGroupDetails()
        } catch {
            errorMessage = "邀请成员失败：\(error.localizedDescription)"
        }
    }

    func removeGroupMember(userId: Int64) async {
        guard let groupId = selectedConversation?.groupId else { return }
        do {
            try await center.removeGroupMember(groupId: groupId, userId: userId)
            await loadSelectedGroupDetails()
        } catch {
            errorMessage = "移除成员失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func leaveSelectedGroup() async -> Bool {
        guard let groupId = selectedConversation?.groupId else { return false }
        do {
            try await center.leaveGroup(groupId: groupId)
            selectedGroupDetail = nil
            selectedGroupMembers = []
            await selectConversation(nil)
            conversations = (try? await store.loadConversations()) ?? []
            return true
        } catch {
            errorMessage = "退出群聊失败：\(error.localizedDescription)"
            return false
        }
    }

    private func reloadParticipantMessages() async {
        var previews: [String: [ImMessage]] = [:]
        for conversation in conversations {
            let recent = ((try? await store.messages(conversationId: conversation.id)) ?? []).reversed()
            var seen: Set<Int64> = []
            previews[conversation.id] = recent.filter { seen.insert($0.senderId).inserted }.prefix(5).map { $0 }
        }
        participantMessagesByConversation = previews
    }

    // MARK: - Contacts (friends / requests / search)

    func refreshContacts() async {
        await center.refreshAll()
        friends = (try? await store.loadFriends()) ?? []
        friendRequests = (try? await store.loadFriendRequests()) ?? []
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
            contactMessage = nil
            return
        }
        isSearchingUsers = true
        contactMessage = nil
        defer { isSearchingUsers = false }
        do {
            userSearchResults = try await center.searchUsers(query: trimmed, limit: 10)
        } catch {
            userSearchResults = []
            contactMessage = "搜索失败：\(error.localizedDescription)"
        }
    }

    /// 加好友搜索结果行的操作状态：已是好友 / 已发送申请 / 提交中 / 可申请。
    func friendSearchActionState(for user: ImPublicUserDTO) -> ImFriendSearchActionState {
        if friends.contains(where: { $0.userId == user.id }) { return .friend }
        guard let selfUserId else { return .available }
        let hasPendingOutgoing = friendRequests.contains {
            $0.senderId == selfUserId && $0.status == "pending" && $0.receiverUsername == user.username
        }
        if hasPendingOutgoing { return .requested }
        if friendRequestSubmittingUsernames.contains(user.username) { return .submitting }
        return .available
    }

    func clearUserSearch() {
        userSearchResults = []
    }

    func sendFriendRequest(username: String, message: String = "") async {
        guard !friendRequestSubmittingUsernames.contains(username) else { return }
        friendRequestSubmittingUsernames.insert(username)
        contactMessage = nil
        defer { friendRequestSubmittingUsernames.remove(username) }
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

    func enterSelectionMode(initialMessageId: String? = nil) {
        isSelectionMode = true
        selectedMessageIds = initialMessageId.map { Set([$0]) } ?? []
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

    // MARK: - Combined forwarding across Agent / peer / group conversations

    func selectedForwardBundle(caption: String = "") -> ForwardedChatBundle? {
        guard let conversation = selectedConversation else { return nil }
        let selected = messages.filter { selectedMessageIds.contains($0.id) }.sorted { $0.seq < $1.seq }
        guard !selected.isEmpty else { return nil }
        return ForwardedChatBundle(
            title: "\(conversation.title)的聊天记录",
            sourceTitle: conversation.title,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            items: selected.map { message in
                let metadata = message.mediaMetadata
                let kind = message.messageType.lowercased()
                return ForwardedChatItem(
                    id: message.id,
                    senderName: message.senderName.isEmpty ? (message.senderId == selfUserId ? "我" : conversation.participantName) : message.senderName,
                    senderAvatar: message.senderAvatar,
                    createdAt: message.createdAt,
                    kind: kind,
                    text: kind == "text" ? message.content : (metadata?.fileName ?? ""),
                    mediaUrl: kind == "text" ? nil : message.content,
                    thumbnailUrl: metadata?.thumbnail
                )
            }
        )
    }

    @discardableResult
    func forwardSelectedMessages(destinationKeys: Set<String>) async -> Bool {
        guard !isForwarding,
              selectedConversation != nil,
              !selectedMessageIds.isEmpty,
              !destinationKeys.isEmpty
        else { return false }
        isForwarding = true
        defer { isForwarding = false }

        guard let bundle = selectedForwardBundle(caption: forwardCaption) else { return false }

        do {
            try await forward(bundle: bundle, destinationKeys: destinationKeys)
            forwardCaption = ""
            isForwardSheetPresented = false
            clearSelection()
            return true
        } catch {
            errorMessage = "转发失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 构建转发目标分页加载器：康纳会话 + IM 会话按最近活跃归并、分页取回，
    /// 转发弹窗按需加载，最终取到全部目标。
    func makeForwardDestinationPager() -> ForwardDestinationPager {
        makeForwardPager() ?? ForwardDestinationPager(
            sessionsLoader: { _, _ in ([], nil) },
            conversationsLoader: { _, _ in ([], nil) }
        )
    }

    /// 转发到 IM 会话仍等待发送完成；转发到康纳会话（agent:*）则立即把智能调用
    /// 放到后台执行并返回，转发弹窗无需等待 LLM 完成即可关闭。
    /// 后台调用失败时优先回传 `onBackgroundError`，缺省落到 `errorMessage`。
    func forward(
        bundle: ForwardedChatBundle,
        destinationKeys: Set<String>,
        onBackgroundError: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws {
        let cardContent = try ForwardedChatBundleCodec.encode(bundle)
        let modelContent = try ForwardedChatBundleCodec.encodeForModel(bundle)
        for key in destinationKeys {
            if key == "agent:new" {
                dispatchAgentForward(modelContent: modelContent, sessionID: nil, onError: onBackgroundError)
            } else if key.hasPrefix("agent:") {
                let id = String(key.dropFirst("agent:".count))
                dispatchAgentForward(modelContent: modelContent, sessionID: id, onError: onBackgroundError)
            } else if key.hasPrefix("im:") {
                let id = String(key.dropFirst("im:".count))
                guard let target = conversations.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
                switch target.kind {
                case .peer:
                    guard let peerID = target.peerUserId else { throw CocoaError(.fileNoSuchFile) }
                    try await center.sendChatMessage(peerId: peerID, content: cardContent)
                case .group:
                    guard let groupID = target.groupId else { throw CocoaError(.fileNoSuchFile) }
                    try await center.sendGroupMessage(groupId: groupID, content: cardContent)
                }
            }
        }
    }

    private func dispatchAgentForward(
        modelContent: String,
        sessionID: String?,
        onError: (@MainActor @Sendable (String) -> Void)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result: String?
                if let sessionID {
                    result = await self.forwardToExistingSession(sessionID, modelContent)
                } else {
                    result = await self.forwardToNewSession(modelContent)
                }
                if result == nil { throw CocoaError(.fileWriteUnknown) }
            } catch {
                let message = "转发失败：\(error.localizedDescription)"
                if let onError {
                    onError(message)
                } else {
                    self.errorMessage = message
                }
            }
        }
    }
}

/// 加好友搜索结果行针对当前用户的可用操作状态。
enum ImFriendSearchActionState {
    case friend
    case requested
    case submitting
    case available
}
