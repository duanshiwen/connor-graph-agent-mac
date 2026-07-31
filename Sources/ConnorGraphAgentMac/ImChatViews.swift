import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

// MARK: - Shared formatting

private enum ImTimeFormat {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static func label(forUnixMilliseconds ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        if Calendar.current.isDateInToday(date) {
            return time.string(from: date)
        }
        return day.string(from: date)
    }
}

// MARK: - Conversation list section (embedded above the AI session list)

/// IM conversations shown above the AI session list; Android renders one mixed
/// list, the Mac list pane keeps a dedicated section (pinned first, newest first).
struct ImConversationListSection: View {
    var model: ImFeatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("好友消息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.socketConnected {
                    Label("离线", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ForEach(model.sortedConversations) { conversation in
                ImConversationRow(
                    conversation: conversation,
                    isSelected: model.selectedConversationId == conversation.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await model.selectConversation(conversation.id) }
                }
                .contextMenu {
                    Button(conversation.pinned ? "取消置顶" : "置顶") {
                        Task { await model.setPinned(conversationId: conversation.id, pinned: !conversation.pinned) }
                    }
                    Button(conversation.muted ? "取消免打扰" : "免打扰") {
                        Task { await model.setMuted(conversationId: conversation.id, muted: !conversation.muted) }
                    }
                    Divider()
                    Button("删除会话", role: .destructive) {
                        Task { await model.deleteConversation(conversation.id) }
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }
}

private struct ImConversationRow: View {
    let conversation: ImConversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: conversation.kind == .group ? "person.3.fill" : "person.crop.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(conversation.title.isEmpty ? "会话" : conversation.title)
                        .font(.body)
                        .lineLimit(1)
                    if conversation.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if conversation.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !conversation.lastMessagePreview.isEmpty {
                    Text(conversation.lastMessagePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ImTimeFormat.label(forUnixMilliseconds: conversation.lastMessageAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if conversation.unreadCount > 0 {
                    Text("\(min(conversation.unreadCount, 99))")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(conversation.muted ? Color.gray : Color.red, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.horizontal, 6)
        )
    }
}

// MARK: - Chat detail (bubbles + composer + multi-select forward)

struct ImChatDetailView: View {
    @Bindable var model: ImFeatureModel
    var chatModel: ChatFeatureModel

    @State private var composerText = ""

    private var conversationTitle: String {
        model.selectedConversation?.title ?? "会话"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            if model.isSelectionMode {
                selectionBar
            } else {
                composer
            }
        }
        .sheet(isPresented: $model.isForwardSheetPresented) {
            ImForwardSheet(model: model, sessions: chatModel.sessions.allSessions)
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(conversationTitle)
                .font(.headline)
                .lineLimit(1)
            if !model.socketConnected {
                Label("连接已断开", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !model.isSelectionMode {
                Button("多选转发", systemImage: "checkmark.circle") {
                    if let last = model.messages.last {
                        model.enterSelectionMode(initialMessageId: last.id)
                    }
                }
                .disabled(model.messages.isEmpty)
            }
            Button("关闭", systemImage: "xmark.circle") {
                Task { await model.selectConversation(nil) }
            }
            .help("返回 AI 会话")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.hasOlderMessages && !model.messages.isEmpty {
                        Button("加载更早的消息") {
                            Task { await model.loadOlderMessages() }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .padding(.top, 8)
                    }
                    ForEach(model.messages) { message in
                        ImMessageBubble(
                            message: message,
                            isMine: message.senderId == (model.selfUserId ?? -1),
                            isGroup: model.selectedConversation?.kind == .group,
                            isSelectionMode: model.isSelectionMode,
                            isSelected: model.selectedMessageIds.contains(message.id),
                            onToggleSelection: { model.toggleMessageSelection(message.id) },
                            onEnterSelection: { model.enterSelectionMode(initialMessageId: message.id) },
                            onRetry: { Task { await model.retryMessage(message.id) } }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.messages.last?.id) { _, newValue in
                if let newValue {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = model.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(model.selectedMessageIds.count) 条")
                .font(.callout)
            Spacer()
            Button("取消") { model.clearSelection() }
            Button("转发给 AI") { model.isForwardSheetPresented = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedMessageIds.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                model.socketConnected ? "发送消息…" : "连接已断开，无法发送",
                text: $composerText
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(sendCurrentMessage)
            .disabled(!model.socketConnected)
            Button("发送", systemImage: "paperplane.fill", action: sendCurrentMessage)
                .buttonStyle(.borderedProminent)
                .disabled(!model.socketConnected || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sendCurrentMessage() {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        composerText = ""
        Task { await model.sendMessage(text) }
    }
}

private struct ImMessageBubble: View {
    let message: ImMessage
    let isMine: Bool
    let isGroup: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEnterSelection: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine && isGroup && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isMine ? Color.accentColor.opacity(0.85) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    Text(ImTimeFormat.label(forUnixMilliseconds: message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isMine {
                        statusView
                    }
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode { onToggleSelection() }
        }
        .contextMenu {
            if !isSelectionMode {
                Button("选择转发", systemImage: "arrowshape.turn.up.right") { onEnterSelection() }
            }
            if message.status == .failed {
                Button("重新发送", systemImage: "arrow.clockwise") { onRetry() }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .delivered:
            Image(systemName: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .read:
            Text("已读")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .failed:
            Button {
                onRetry()
            } label: {
                Label("重发", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Forward sheet (caption + target AI session)

/// Android `ForwardToAgentSheet`: optional caption, target session picker
/// (new session by default), then the anonymized forward flow.
struct ImForwardSheet: View {
    @Bindable var model: ImFeatureModel
    var sessions: [AgentSession]

    @State private var targetSessionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转发给 AI")
                .font(.headline)
            Text("已选 \(model.selectedMessageIds.count) 条消息。转发前将自动脱敏：好友身份替换为不透明代号，手机号、邮箱等敏感信息将被隐藏。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("留言（可选）", text: $model.forwardCaption)
                .textFieldStyle(.roundedBorder)

            Picker("目标会话", selection: $targetSessionID) {
                Text("新建会话").tag(String?.none)
                ForEach(sessions) { session in
                    Text(session.title).tag(Optional(session.id))
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    model.isForwardSheetPresented = false
                }
                Button(model.isForwarding ? "转发中…" : "转发") {
                    Task { await model.forwardSelectedMessages(targetSessionId: targetSessionID) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isForwarding || model.selectedMessageIds.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - 通讯录 (friends / requests / user search)

/// Android `ImContactsScreen`: friend list with message / person-binding / removal
/// actions, incoming and outgoing friend requests, and user search to add friends.
struct ImContactsDetailView: View {
    var model: ImFeatureModel
    var contacts: ContactsFeatureModel
    var onOpenPeerChat: (Int64) -> Void

    @State private var searchQuery = ""
    @State private var requestUsername = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let message = model.contactMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                searchSection
                if !incomingPendingRequests.isEmpty || !outgoingPendingRequests.isEmpty {
                    requestsSection
                }
                friendsSection
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("通讯录")
        .task {
            await model.refreshContacts()
        }
    }

    private var incomingPendingRequests: [ImFriendRequest] {
        guard let selfId = model.selfUserId else { return [] }
        return model.friendRequests.filter { $0.receiverId == selfId && $0.status == "pending" }
    }

    private var outgoingPendingRequests: [ImFriendRequest] {
        guard let selfId = model.selfUserId else { return [] }
        return model.friendRequests.filter { $0.senderId == selfId && $0.status == "pending" }
    }

    // MARK: 添加好友

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添加好友")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("搜索用户名 / 昵称", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.searchUsers(query: searchQuery) } }
                Button("搜索") {
                    Task { await model.searchUsers(query: searchQuery) }
                }
            }
            ForEach(model.userSearchResults, id: \.id) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.nickname.isEmpty ? user.username : user.nickname)
                            .font(.body)
                        Text("@\(user.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.friends.contains(where: { $0.userId == user.id }) {
                        Text("已是好友")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("加好友") {
                            Task { await model.sendFriendRequest(username: user.username) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 好友请求

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("好友请求")
                .font(.headline)
            ForEach(incomingPendingRequests) { request in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.senderNickname.isEmpty ? request.senderUsername : request.senderNickname)
                            .font(.body)
                        if !request.message.isEmpty {
                            Text(request.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("同意") {
                        Task { await model.acceptFriendRequest(requestId: request.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("拒绝") {
                        Task { await model.rejectFriendRequest(requestId: request.id) }
                    }
                }
                .padding(.vertical, 2)
            }
            ForEach(outgoingPendingRequests) { request in
                HStack {
                    Text(request.receiverNickname.isEmpty ? request.receiverUsername : request.receiverNickname)
                        .font(.body)
                    Spacer()
                    Text("等待对方同意")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 好友列表

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("好友（\(model.friends.count)）")
                    .font(.headline)
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await model.refreshContacts() }
                }
                .buttonStyle(.borderless)
            }
            if model.friends.isEmpty {
                Text(model.isSignedIn ? "还没有好友，先搜索用户加好友吧。" : "登录康纳账号后即可添加好友聊天。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.friends) { friend in
                ImFriendRow(
                    friend: friend,
                    boundPersonName: boundPersonName(for: friend),
                    profiles: contacts.profiles,
                    onMessage: { onOpenPeerChat(friend.userId) },
                    onBind: { personProfileID in
                        Task { await model.bindFriendPerson(userId: friend.userId, personProfileID: personProfileID) }
                    },
                    onRemove: {
                        Task { await model.removeFriend(userId: friend.userId) }
                    }
                )
            }
        }
    }

    private func boundPersonName(for friend: ImFriend) -> String? {
        guard let personProfileID = friend.personProfileID else { return nil }
        return contacts.profiles.first { $0.id.rawValue == personProfileID }?.displayName
    }
}

private struct ImFriendRow: View {
    let friend: ImFriend
    let boundPersonName: String?
    let profiles: [PersonProfile]
    let onMessage: () -> Void
    let onBind: (String?) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text("@\(friend.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let boundPersonName {
                        Label(boundPersonName, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
            }
            Spacer()
            Button("发消息", systemImage: "bubble.left.fill", action: onMessage)
            Menu("关联人物") {
                ForEach(profiles) { profile in
                    Button(profile.displayName) { onBind(profile.id.rawValue) }
                }
                if friend.personProfileID != nil {
                    Divider()
                    Button("解除关联", role: .destructive) { onBind(nil) }
                }
            }
            .frame(width: 110)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .help("删除好友")
        }
        .padding(.vertical, 4)
    }
}
