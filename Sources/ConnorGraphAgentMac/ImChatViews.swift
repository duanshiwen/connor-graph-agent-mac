import SwiftUI
import AppKit
import UniformTypeIdentifiers
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

private enum ImChatLayout {
    static let messageBubbleMaxWidth: CGFloat = 420
}

// MARK: - Conversation list row

struct ImConversationRow: View {
    let conversation: ImConversation
    let participantMessages: [ImMessage]
    let selfUserId: Int64?
    let selfAvatarURL: String
    let selfAvatarRevision: UInt
    let isSelected: Bool
    let isRegeneratingTitle: Bool
    let labelDefinitions: [AgentSessionLabelDefinition]
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onSetStatus: (AgentSessionStatus) -> Void
    let onToggleLabel: (String) -> Void
    let onRegenerateTitle: () -> Void
    let onToggleMuted: () -> Void
    let onDelete: () -> Void

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppListCardLayout.contentPadding) {
            Image(systemName: statusIcon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: AppListCardLayout.contentSpacing) {
                titleRow
                metadataRow
                labelRow
                participantRow
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

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(conversation.status.displayName)
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.14), in: Capsule())
            Text(conversation.lastMessagePreview.isEmpty ? conversationKindLabel : conversation.lastMessagePreview)
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
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

    private var participantRow: some View {
        HStack(spacing: 6) {
            ImParticipantAvatarStack(
                conversation: conversation,
                messages: participantMessages,
                selfUserId: selfUserId,
                selfAvatarURL: selfAvatarURL,
                selfAvatarRevision: selfAvatarRevision
            )
                .fixedSize(horizontal: true, vertical: false)
            Text(conversation.participantName)
                .font(AppListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conversationKindLabel: String {
        conversation.kind == .peer ? "联系人会话" : "群组会话"
    }

    private var statusColor: Color {
        AppSessionStatusVisualStyle.color(for: conversation.status)
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
    let selfUserId: Int64?
    let selfAvatarURL: String
    let selfAvatarRevision: UInt

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(avatars.prefix(5).enumerated()), id: \.offset) { _, avatar in
                ImUserAvatar(
                    urlString: avatar.url,
                    name: avatar.name,
                    size: 20,
                    revision: avatar.revision
                )
            }
            if avatars.count >= 5 {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .accessibilityLabel("更多成员")
            }
        }
        .frame(minWidth: 20, alignment: .leading)
    }

    private var avatars: [(url: String, name: String, revision: UInt)] {
        if conversation.kind == .peer {
            return [(conversation.avatar, conversation.participantName, 0)]
        }
        let messageAvatars: [(url: String, name: String, revision: UInt)] = messages.map { message in
            if message.senderId == selfUserId {
                return (selfAvatarURL, message.senderName, selfAvatarRevision)
            }
            return (message.senderAvatar, message.senderName, UInt(0))
        }
        return messageAvatars.isEmpty
            ? [(conversation.avatar, conversation.participantName, UInt(0))]
            : messageAvatars
    }
}

private struct ImUserAvatar: View {
    let urlString: String
    let name: String
    let size: CGFloat
    var revision: UInt = 0

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            initials
            ReloadingAvatarImage(urlString: urlString, revision: revision)
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

    @State private var composerText = ""
    @State private var voiceRecorder = ImVoiceRecorder()
    @State private var mediaPlayback = ImMediaPlaybackController()
    @State private var isConversationInfoPresented = false
    @State private var mediaPreview: ChatMediaPreviewItem?
    @State private var isAttachmentLibraryPresented = false
    @State private var attachmentLibraryModel: AttachmentLibraryPickerModel?

    private var conversationTitle: String {
        model.selectedConversation?.title ?? "会话"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            if model.isSelectionMode {
                selectionBar
            } else {
                composer
            }
        }
        .sheet(isPresented: $model.isForwardSheetPresented) {
            if let bundle = model.selectedForwardBundle() {
                ForwardDestinationSheet(
                    bundle: bundle,
                    pager: model.makeForwardDestinationPager(),
                    isSending: model.isForwarding,
                    onCancel: { model.isForwardSheetPresented = false },
                    onSend: { caption, destinationKeys in
                        model.forwardCaption = caption
                        _ = await model.forwardSelectedMessages(destinationKeys: destinationKeys)
                    }
                )
            }
        }
        .sheet(isPresented: $isConversationInfoPresented) {
            ImConversationInfoSheet(model: model, isPresented: $isConversationInfoPresented)
        }
        .overlay {
            if let mediaPreview {
                ChatMediaPreviewOverlay(item: mediaPreview, onClose: { self.mediaPreview = nil })
                    .transition(.opacity)
            }
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
        ZStack {
            Text(conversationTitle)
                .font(AgentChatTypography.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 220)

            HStack(spacing: AgentChatLayout.spaceS) {
                if !model.socketConnected {
                    Label("连接已断开", systemImage: "wifi.slash")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if !model.isSelectionMode {
                    Button("选择消息", systemImage: "checkmark.circle") {
                        model.enterSelectionMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.messages.isEmpty)
                    .help("选择多条消息并合并转发")
                }
                Button {
                    isConversationInfoPresented = true
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                }
                .buttonStyle(.borderless)
                .help("会话信息")
                .accessibilityLabel("打开会话信息")
            }
        }
        .padding(.horizontal, AgentChatLayout.spaceL)
        .padding(.top, AgentChatLayout.spaceS)
        .padding(.bottom, AgentChatLayout.spaceL)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AgentChatLayout.conversationTurnSpacing) {
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
                            conversation: model.selectedConversation,
                            isMine: message.senderId == (model.selfUserId ?? -1),
                            selfAvatarURL: model.selfAvatarURL,
                            selfAvatarRevision: model.selfAvatarRevision,
                            isGroup: model.selectedConversation?.kind == .group,
                            isSelectionMode: model.isSelectionMode,
                            isSelected: model.selectedMessageIds.contains(message.id),
                            onToggleSelection: { model.toggleMessageSelection(message.id) },
                            onEnterSelection: { model.enterSelectionMode(initialMessageId: message.id) },
                            onRetry: { Task { await model.retryMessage(message.id) } },
                            onOpenMedia: { mediaPreview = $0 },
                            playback: mediaPlayback
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: AgentChatLayout.chatContentMaxWidth)
                .padding(.horizontal, AgentChatLayout.chatViewportSpacing)
                .padding(.vertical, AgentChatLayout.chatViewportVerticalInset)
                .frame(maxWidth: .infinity)
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
            Button("合并转发") { model.isForwardSheetPresented = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedMessageIds.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            TextField(
                model.socketConnected ? "发送消息…" : "连接已断开，无法发送",
                text: $composerText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...6)
            .font(AgentChatTypography.body)
            .onSubmit(sendCurrentMessage)
            .disabled(!model.socketConnected)
            .padding(.horizontal, AgentChatLayout.spaceL)
            .padding(.vertical, AgentChatLayout.spaceM)
            .frame(
                minHeight: AgentChatLayout.composerTextMinHeight,
                maxHeight: AgentChatLayout.composerTextMaxHeight,
                alignment: .topLeading
            )

            HStack(spacing: AgentChatLayout.spaceS) {
                Menu {
                    Button("图片", systemImage: "photo") { chooseMedia(type: .image) }
                    Button("视频", systemImage: "video") { chooseMedia(type: .video) }
                    Button("音频文件", systemImage: "waveform") { chooseMedia(type: .audio) }
                    Button("文件", systemImage: "doc") { chooseMedia(type: .file) }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(!model.socketConnected || model.isSendingMedia || voiceRecorder.isRecording)
                .help("发送图片、视频、音频或文件")

                Button {
                    toggleVoiceRecording()
                } label: {
                    Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                        .foregroundStyle(voiceRecorder.isRecording ? .red : .secondary)
                        .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                }
                .buttonStyle(.plain)
                .disabled(!model.socketConnected || model.isSendingMedia)
                .help(voiceRecorder.isRecording ? "停止并发送语音" : "录制语音")

                if voiceRecorder.isRecording {
                    Text("\(voiceRecorder.elapsedSeconds)s / 60s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if model.isSendingMedia {
                    ProgressView().controlSize(.small).help("正在上传媒体")
                }

                Spacer(minLength: AgentChatLayout.spaceXS)

                AgentSendControlButton(
                    isSubmitting: false,
                    isDisabled: !model.socketConnected || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: sendCurrentMessage
                )
                .fixedSize()
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceS)
            .frame(minHeight: AgentChatLayout.hitTargetSize)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: AgentChatLayout.chatContentMaxWidth)
        .padding(.horizontal, AgentChatLayout.chatViewportSpacing)
        .padding(.bottom, AgentChatLayout.spaceM)
        .frame(maxWidth: .infinity)
        .onChange(of: voiceRecorder.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, let recording = voiceRecorder.takeFinishedRecording() else { return }
            sendRecording(recording)
        }
        .sheet(isPresented: $isAttachmentLibraryPresented) {
            if let model = attachmentLibraryModel {
                AttachmentLibraryPickerView(
                    model: model,
                    title: "附件库 · 发送附件",
                    onPick: { urls in
                        isAttachmentLibraryPresented = false
                        guard let url = urls.first else { return }
                        sendMedia(type: model.kindFilter == .image ? .image
                                        : model.kindFilter == .video ? .video
                                        : model.kindFilter == .audio ? .audio
                                        : .file, url: url)
                    },
                    onPickFromFolder: {
                        isAttachmentLibraryPresented = false
                        let type: ImMessageType = model.kindFilter == .image ? .image
                            : model.kindFilter == .video ? .video
                            : model.kindFilter == .audio ? .audio
                            : .file
                        folderPick(type: type)
                    }
                )
            }
        }
    }

    private func sendCurrentMessage() {
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        composerText = ""
        Task { await model.sendMessage(text) }
    }

    /// 发附件默认打开附件库（按类型筛选的最近附件）；库为空或要选库外文件时回退文件夹。
    private func chooseMedia(type: ImMessageType) {
        guard let paths = try? AppStoragePaths.live() else {
            folderPick(type: type)
            return
        }
        let preset: AttachmentLibraryPickerModel.KindFilter = switch type {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .file, .text, .system: .all
        }
        attachmentLibraryModel = AttachmentLibraryPickerModel(
            store: FileArtifactStore(paths: paths),
            allowsMultipleSelection: false,
            presetKind: preset
        )
        isAttachmentLibraryPresented = true
    }

    private func folderPick(type: ImMessageType) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = switch type {
        case .image: [.image]
        case .video: [.movie]
        case .audio: [.audio]
        case .file: [
            "pdf", "txt", "md", "csv", "json", "rtf", "doc", "docx", "xls", "xlsx",
            "ppt", "pptx", "odt", "ods", "odp",
        ].compactMap { UTType(filenameExtension: $0) }
        case .text, .system: []
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sendMedia(type: type, url: url)
    }

    private func sendMedia(type: ImMessageType, url: URL) {
        Task {
            let metadata = await ImMediaInspector.metadata(for: url, type: type)
            await model.sendMedia(fileURL: url, messageType: type, metadata: metadata)
        }
    }

    private func toggleVoiceRecording() {
        if voiceRecorder.isRecording {
            if let recording = voiceRecorder.stop() { sendRecording(recording) }
        } else {
            Task {
                do { try await voiceRecorder.start() }
                catch { model.errorMessage = "录音失败：\(error.localizedDescription)" }
            }
        }
    }

    private func sendRecording(_ recording: (url: URL, duration: Int)) {
        Task {
            let metadata = await ImMediaInspector.metadata(
                for: recording.url,
                type: .audio,
                duration: recording.duration
            )
            await model.sendMedia(fileURL: recording.url, messageType: .audio, metadata: metadata)
            try? FileManager.default.removeItem(at: recording.url)
        }
    }
}

// MARK: - Normal group management

struct ImCreateGroupSheet: View {
    @Bindable var model: ImFeatureModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var description = ""
    @State private var selectedMemberIDs: Set<Int64> = []
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建群聊").font(.headline)
                Spacer()
                Button("取消") { isPresented = false }
                Button("创建") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
            .padding(16)
            Divider()

            Form {
                TextField("群名称", text: $name)
                TextField("群描述（可选）", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                Section("选择成员") {
                    if model.friends.isEmpty {
                        Text("暂无好友").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.friends) { friend in
                            Toggle(isOn: memberBinding(friend.userId)) {
                                HStack(spacing: 10) {
                                    ImUserAvatar(urlString: friend.avatar, name: friend.displayName, size: 28)
                                    Text(friend.displayName)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 520)
    }

    private func memberBinding(_ userId: Int64) -> Binding<Bool> {
        Binding(
            get: { selectedMemberIDs.contains(userId) },
            set: { selected in
                if selected { selectedMemberIDs.insert(userId) }
                else { selectedMemberIDs.remove(userId) }
            }
        )
    }

    private func create() {
        isCreating = true
        Task {
            let created = await model.createGroup(
                name: name,
                description: description,
                memberIds: selectedMemberIDs.sorted()
            )
            isCreating = false
            if created { isPresented = false }
        }
    }
}

struct ImGroupDetailSheet: View {
    @Bindable var model: ImFeatureModel
    @Binding var isPresented: Bool

    private var memberIDs: Set<Int64> { Set(model.selectedGroupMembers.map(\.userId)) }
    private var inviteCandidates: [ImFriend] { model.friends.filter { !memberIDs.contains($0.userId) } }
    private var isOwner: Bool { model.selectedGroupDetail?.creatorId == model.selfUserId }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("群聊详情").font(.headline)
                Spacer()
                Button("完成") { isPresented = false }
            }
            .padding(16)
            Divider()

            if model.isLoadingGroupDetails && model.selectedGroupDetail == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let group = model.selectedGroupDetail {
                Form {
                    LabeledContent("群名称", value: group.name)
                    if !group.description.isEmpty {
                        LabeledContent("群描述", value: group.description)
                    }
                    LabeledContent("成员", value: "\(model.selectedGroupMembers.count) 人")

                    Section("成员列表") {
                        ForEach(model.selectedGroupMembers) { member in
                            HStack(spacing: 10) {
                                ImUserAvatar(urlString: member.avatar, name: member.displayName, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                    if member.userId == group.creatorId {
                                        Text("群主").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if isOwner && member.userId != group.creatorId {
                                    Button("移除", role: .destructive) {
                                        Task { await model.removeGroupMember(userId: member.userId) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    if !inviteCandidates.isEmpty {
                        Section("邀请好友") {
                            ForEach(inviteCandidates) { friend in
                                HStack(spacing: 10) {
                                    ImUserAvatar(urlString: friend.avatar, name: friend.displayName, size: 28)
                                    Text(friend.displayName)
                                    Spacer()
                                    Button("邀请") {
                                        Task { await model.inviteGroupMember(userId: friend.userId) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    Section {
                        Button("退出群聊", role: .destructive) {
                            Task {
                                if await model.leaveSelectedGroup() { isPresented = false }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("无法加载群聊", systemImage: "person.3")
            }
        }
        .frame(width: 480, height: 600)
        .task { await model.loadSelectedGroupDetails() }
    }
}

private struct ImConversationInfoSheet: View {
    @Bindable var model: ImFeatureModel
    @Binding var isPresented: Bool

    var body: some View {
        if model.selectedConversation?.kind == .group {
            ImGroupDetailSheet(model: model, isPresented: $isPresented)
        } else {
            peerDetails
        }
    }

    private var peerDetails: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话信息").font(.headline)
                Spacer()
                Button("完成") { isPresented = false }
            }
            .padding(16)
            Divider()

            if let conversation = model.selectedConversation {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            ImUserAvatar(
                                urlString: conversation.avatar,
                                name: conversation.participantName,
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conversation.title).font(.headline)
                                Text("跟 \(conversation.participantName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("会话") {
                        LabeledContent("类型", value: "单聊")
                        LabeledContent("状态", value: conversation.status.displayName)
                        LabeledContent("消息", value: "\(model.messages.count) 条")
                        LabeledContent("通知", value: conversation.muted ? "已静音" : "正常")
                    }
                    if !conversation.labelIds.isEmpty {
                        Section("标签") {
                            Text(conversation.labelIds.joined(separator: " · "))
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("无法加载会话", systemImage: "info.circle")
            }
        }
        .frame(width: 420, height: 430)
    }
}

private struct ImMessageBubble: View {
    let message: ImMessage
    let conversation: ImConversation?
    let isMine: Bool
    let selfAvatarURL: String
    let selfAvatarRevision: UInt
    let isGroup: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEnterSelection: () -> Void
    let onRetry: () -> Void
    let onOpenMedia: (ChatMediaPreviewItem) -> Void
    var playback: ImMediaPlaybackController

    @State private var forwardedDetail: ForwardedChatBundle?

    @AppStorage(AgentChatFontPreferences.messageBodyPointSizeKey)
    private var preferredMessageBodyPointSize = AgentChatFontPreferences.defaultMessageBodyPointSize

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            if isMine { Spacer(minLength: AgentChatLayout.messageSideInset) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: AgentChatLayout.spaceXS) {
                identityRow

                messageContent
                HStack(spacing: 4) {
                    Text(ImTimeFormat.label(forUnixMilliseconds: message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isMine {
                        statusView
                    }
                }
            }
            if !isMine { Spacer(minLength: AgentChatLayout.messageSideInset) }
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

    private var messageBodyPointSize: CGFloat {
        AgentChatFontPreferences.validatedMessageBodyPointSize(preferredMessageBodyPointSize)
    }

    private var displayName: String {
        let sender = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sender.isEmpty { return sender }
        if isMine { return "我" }
        return conversation?.participantName ?? (isGroup ? "群成员" : "好友")
    }

    private var avatarURL: String {
        if isMine { return selfAvatarURL }
        if !message.senderAvatar.isEmpty { return message.senderAvatar }
        return conversation?.avatar ?? ""
    }

    @ViewBuilder
    private var messageContent: some View {
        if let bundle = ForwardedChatBundleCodec.decode(message.content) {
            ForwardedChatCard(bundle: bundle, onOpen: { forwardedDetail = bundle })
                .frame(maxWidth: ImChatLayout.messageBubbleMaxWidth)
                .sheet(item: $forwardedDetail) { selected in
                    ForwardedChatDetailView(bundle: selected, onClose: { forwardedDetail = nil })
                }
        } else {
        if message.mediaMetadata?.attachmentKind == "file" {
            ImFileMessageContent(message: message, isMine: isMine, onOpenMedia: onOpenMedia)
        } else {
        switch message.type {
        case .text, .system:
            Text(message.content)
                .font(AgentChatTypography.messageBody(pointSize: messageBodyPointSize))
                .textSelection(.enabled)
                .padding(.horizontal, AgentChatLayout.messageBubbleHorizontalPadding)
                .padding(.vertical, AgentChatLayout.messageBubbleVerticalPadding)
                .background(
                    isMine ? ConnorCraftPalette.userBubble : Color.secondary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                )
                .frame(
                    maxWidth: ImChatLayout.messageBubbleMaxWidth,
                    alignment: isMine ? .trailing : .leading
                )
        case .image:
            ImImageMessageContent(message: message, isMine: isMine, onOpenMedia: onOpenMedia)
        case .video:
            ImVideoMessageContent(message: message, isMine: isMine, onOpenMedia: onOpenMedia)
        case .audio:
            ImAudioMessageContent(message: message, isMine: isMine, playback: playback)
        case .file:
            ImFileMessageContent(message: message, isMine: isMine, onOpenMedia: onOpenMedia)
        case nil:
            Label(
                message.messageType.lowercased() == "location" ? "不支持的位置消息" : "不支持的消息",
                systemImage: "nosign"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceS)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM))
        }
        }
        }
    }

    private var identityRow: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            if isMine { Spacer(minLength: 0) }
            ImUserAvatar(
                urlString: avatarURL,
                name: displayName,
                size: AgentChatLayout.avatarSize,
                revision: isMine ? selfAvatarRevision : 0
            )
            Text(displayName)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.primary.opacity(0.88))
            if !isMine { Spacer(minLength: 0) }
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

private struct ImImageMessageContent: View {
    let message: ImMessage
    let isMine: Bool
    let onOpenMedia: (ChatMediaPreviewItem) -> Void

    var body: some View {
        if isExpired {
            ImExpiredMediaContent(icon: "photo", label: "图片", isMine: isMine)
        } else if let url = displayURL {
            Button {
                onOpenMedia(ChatMediaPreviewItem(type: .image, url: url, title: metadata.fileName ?? "图片"))
            } label: {
                ChatThumbnailImage(url: url, width: 240, height: imageHeight)
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusM))
            .help("放大预览图片")
        }
    }

    private var metadata: ImMediaMetadata { message.mediaMetadata ?? ImMediaMetadata() }
    private var isExpired: Bool { metadata.expired && localURL == nil }
    private var localURL: URL? {
        guard let path = metadata.localPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
    private var displayURL: URL? { localURL ?? URL(string: message.content) }
    private var imageHeight: CGFloat {
        guard let width = metadata.width, let height = metadata.height, width > 0, height > 0 else { return 180 }
        return min(300, max(120, 240 * CGFloat(height) / CGFloat(width)))
    }
}

private struct ImVideoMessageContent: View {
    let message: ImMessage
    let isMine: Bool
    let onOpenMedia: (ChatMediaPreviewItem) -> Void

    var body: some View {
        if isExpired {
            ImExpiredMediaContent(icon: "video", label: "视频", isMine: isMine)
        } else {
            Button(action: openVideo) {
                ZStack {
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusM)
                        .fill(Color.black.opacity(0.78))
                        .frame(width: 240, height: 150)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                    if let duration = metadata.duration {
                        Text(Self.durationLabel(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .frame(width: 230, height: 140, alignment: .bottomTrailing)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("播放视频")
        }
    }

    private var metadata: ImMediaMetadata { message.mediaMetadata ?? ImMediaMetadata() }
    private var displayURL: URL? {
        if let path = metadata.localPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(string: message.content)
    }
    private var isExpired: Bool { metadata.expired && displayURL == nil }
    private func openVideo() {
        guard let displayURL else { return }
        onOpenMedia(ChatMediaPreviewItem(type: .video, url: displayURL, title: metadata.fileName ?? "视频"))
    }
    private static func durationLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ImAudioMessageContent: View {
    let message: ImMessage
    let isMine: Bool
    var playback: ImMediaPlaybackController

    var body: some View {
        if isExpired {
            ImExpiredMediaContent(icon: "waveform", label: "语音", isMine: isMine)
        } else {
            Button {
                guard let displayURL else { return }
                playback.toggle(messageID: message.id, url: displayURL)
            } label: {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    Text("\(metadata.duration ?? 0)\"")
                        .monospacedDigit()
                }
                .font(.callout)
                .padding(.horizontal, AgentChatLayout.spaceM)
                .padding(.vertical, AgentChatLayout.spaceS)
                .frame(minWidth: 132)
                .background(
                    isMine ? ConnorCraftPalette.userBubble : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL)
                )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停语音" : "播放语音")
        }
    }

    private var metadata: ImMediaMetadata { message.mediaMetadata ?? ImMediaMetadata() }
    private var displayURL: URL? {
        if let path = metadata.localPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(string: message.content)
    }
    private var isExpired: Bool { metadata.expired && displayURL == nil }
    private var isPlaying: Bool { playback.playingMessageID == message.id }
}

private struct ImFileMessageContent: View {
    let message: ImMessage
    let isMine: Bool
    let onOpenMedia: (ChatMediaPreviewItem) -> Void

    var body: some View {
        Button {
            guard let displayURL else { return }
            onOpenMedia(ChatMediaPreviewItem(type: .file, url: displayURL, title: metadata.fileName ?? "文件"))
        } label: {
            HStack(spacing: AgentChatLayout.spaceS) {
                Image(systemName: "doc")
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.fileName ?? "文件").lineLimit(2)
                    if let size = metadata.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceS)
            .background(
                isMine ? ConnorCraftPalette.userBubble : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL)
            )
        }
        .buttonStyle(.plain)
        .disabled(displayURL == nil)
        .help("预览文件")
    }

    private var metadata: ImMediaMetadata { message.mediaMetadata ?? ImMediaMetadata() }
    private var displayURL: URL? {
        if let path = metadata.localPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(string: message.content)
    }
}

private struct ImExpiredMediaContent: View {
    let icon: String
    let label: String
    let isMine: Bool

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: icon)
            Text("\(label)消息")
            Text("消息已过期").foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceS)
        .background(
            isMine ? ConnorCraftPalette.userBubble : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL)
        )
    }
}

// MARK: - Forward sheet compatibility wrapper

/// Android `ForwardToAgentSheet`: optional caption, target session picker
/// (new session by default), then the anonymized forward flow.
struct ImForwardSheet: View {
    @Bindable var model: ImFeatureModel

    var body: some View {
        if let bundle = model.selectedForwardBundle() {
            ForwardDestinationSheet(
                bundle: bundle,
                pager: model.makeForwardDestinationPager(),
                isSending: model.isForwarding,
                onCancel: { model.isForwardSheetPresented = false },
                onSend: { caption, keys in
                    model.forwardCaption = caption
                    _ = await model.forwardSelectedMessages(destinationKeys: keys)
                }
            )
        }
    }
}
