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
// MARK: - Conversation list row

struct ImConversationRow: View {
    let conversation: ImConversation
    let participantMessages: [ImMessage]
    let isSelected: Bool
    let isRegeneratingTitle: Bool
    let labelDefinitions: [AgentSessionLabelDefinition]
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onSetStatus: (AgentSessionStatus) -> Void
    let onToggleLabel: (String) -> Void
    let onRegenerateTitle: () -> Void
    let onTogglePinned: () -> Void
    let onToggleMuted: () -> Void
    let onDelete: () -> Void

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppListCardLayout.contentPadding) {
            Image(systemName: conversation.pinned ? "pin.fill" : statusIcon)
                .foregroundStyle(conversation.pinned ? .orange : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: AppListCardLayout.contentSpacing) {
                titleRow
                participantRow
                labelRow
            }
        }
        .appListRowSurface(isSelected: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditingTitle { onSelect() } }
        .onAppear { titleDraft = conversation.title }
        .onChange(of: conversation.title) { _, title in if !isEditingTitle { titleDraft = title } }
        .onChange(of: isTitleFocused) { _, focused in if !focused && isEditingTitle { commitTitleEdit() } }
        .contextMenu { contextMenu }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isEditingTitle {
                TextField("会话标题", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                    .focused($isTitleFocused)
                    .onSubmit(commitTitleEdit)
            } else {
                Text(conversation.title.isEmpty ? "会话" : conversation.title)
                    .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                    .lineLimit(AppListCardLayout.titleLineLimit)
                    .onTapGesture(count: 2, perform: beginTitleEdit)
            }
            if conversation.muted {
                Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isRegeneratingTitle {
                ProgressView().controlSize(.small)
            } else {
                Text(ImTimeFormat.label(forUnixMilliseconds: conversation.lastMessageAt))
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var participantRow: some View {
        HStack(spacing: 6) {
            ImParticipantAvatarStack(conversation: conversation, messages: participantMessages)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(conversation.participantName)
                .font(AppListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(conversation.status.displayName)
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(Color.accentColor)
            if conversation.unreadCount > 0 {
                Text("\(min(conversation.unreadCount, 99))")
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(conversation.muted ? Color.gray : Color.red, in: Capsule())
            }
        }
    }

    @ViewBuilder private var labelRow: some View {
        if !conversation.labelIds.isEmpty {
            HStack(spacing: 4) {
                ForEach(conversation.labelIds.prefix(3), id: \.self) { labelID in
                    Text(labelDefinitions.first(where: { $0.id == labelID })?.name ?? labelID)
                        .font(AppListTypography.rowCaption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.10), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Menu("更改状态", systemImage: "circle.dashed") {
            ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button(status.displayName) { onSetStatus(status) }
            }
        }
        Menu("标签", systemImage: "tag") {
            ForEach(labelDefinitions) { definition in
                Button {
                    onToggleLabel(definition.id)
                } label: {
                    Label(definition.name, systemImage: conversation.labelIds.contains(definition.id) ? "checkmark.circle.fill" : "tag")
                }
            }
        }
        Divider()
        Button("重命名", systemImage: "pencil", action: beginTitleEdit)
        Button("AI 重设标题", systemImage: "sparkles", action: onRegenerateTitle).disabled(isRegeneratingTitle)
        Button(conversation.pinned ? "取消置顶" : "置顶", systemImage: "pin", action: onTogglePinned)
        Button(conversation.muted ? "取消免打扰" : "免打扰", systemImage: "bell.slash", action: onToggleMuted)
        Divider()
        Button("删除会话", systemImage: "trash", role: .destructive, action: onDelete)
    }

    private var statusIcon: String {
        AgentSessionStatusDefinition.defaults.first(where: { $0.id == conversation.status.rawValue })?.systemImage ?? "circle"
    }

    private func beginTitleEdit() {
        titleDraft = conversation.title
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard !title.isEmpty, title != conversation.title else { return }
        onRename(title)
    }
}

private struct ImParticipantAvatarStack: View {
    let conversation: ImConversation
    let messages: [ImMessage]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(avatars.prefix(5).enumerated()), id: \.offset) { _, avatar in
                ImUserAvatar(urlString: avatar.url, name: avatar.name, size: 20)
            }
        }
        .frame(minWidth: 20, alignment: .leading)
    }

    private var avatars: [(url: String, name: String)] {
        if conversation.kind == .peer { return [(conversation.avatar, conversation.participantName)] }
        let messageAvatars = messages.map { ($0.senderAvatar, $0.senderName) }
        return messageAvatars.isEmpty ? [(conversation.avatar, conversation.participantName)] : messageAvatars
    }
}

private struct ImUserAvatar: View {
    let urlString: String
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
    }

    private var initials: some View {
        Text(name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?")
            .font(.system(size: max(9, size * 0.48), weight: .semibold))
            .foregroundStyle(Color.accentColor)
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
