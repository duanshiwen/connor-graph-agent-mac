import SwiftUI
import AppKit
import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentChatView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var imModel: ImFeatureModel? = nil
    @State private var isSessionInfoPresented = false


    var body: some View {
        Group {
            if model.sessions.selectedSessionID == nil && !chatActions.dependencies.browser.isVisible {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                activeSessionContent
            }
        }
        .onAppear {
            chatActions.session.reloadChatSessionsIfNeededAfterInitialLoad()
            chatActions.approval.reloadPendingApprovals()
        }
        .onChange(of: model.sessions.selectedSessionID) { _, _ in
            model.workspaceExplorer.dismissTree()
            model.dismissPreviewsForSessionChange()
        }
    }

    private var activeSessionContent: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if chatActions.dependencies.browser.isVisible {
                    BrowserWorkspaceView(
                        model: chatActions.dependencies.browser,
                        chat: BrowserWorkspaceChatActions(
                            selectedSessionID: model.sessions.selectedSessionID,
                            isSubmitting: model.run.isSubmitting,
                            defaultSearchEngine: chatActions.dependencies.appSettings.defaultSearchEngine,
                            shortcutSettings: chatActions.dependencies.inputSettings.shortcutSettings,
                            cancelActiveRun: { chatActions.run.cancelActiveChatRun() },
                            appendToDraft: { chatActions.composer.appendToSelectedChatInputDraft($0) },
                            appendSessionRecord: { kind, title, body, metadata, sessionID in
                                chatActions.workspace.appendSessionRecord(kind: kind, title: title, body: body, metadata: metadata, sessionID: sessionID)
                            },
                            submit: { prompt, displayPrompt in
                                await chatActions.run.submitChat(prompt: prompt, displayPrompt: displayPrompt)
                            },
                            currentErrorMessage: { chatActions.errors.errorMessage },
                            reportError: { chatActions.errors.errorMessage = $0 }
                        )
                    )
                } else {
                    AgentChatConversationView(model: model, chatActions: chatActions, imModel: imModel, isSessionInfoPresented: $isSessionInfoPresented)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isSessionInfoPresented {
                AgentChatInspectorView(model: model, chatActions: chatActions, isPresented: $isSessionInfoPresented)
                    .frame(width: 360, height: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                            .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                    .padding(.top, AgentChatLayout.spaceL)
                    .padding(.trailing, AgentChatLayout.spaceL)
            }

            if let toast = model.composer.attachmentToast {
                AgentChatToastView(toast: toast) {
                    model.composer.attachmentToast = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(8)
                .padding(.top, AgentChatLayout.spaceL)
                    .padding(.trailing, AgentChatLayout.spaceL)
            }

            if model.workspaceExplorer.isTreePresented {
                WorkspaceFileTreeOverlay(
                    model: model.workspaceExplorer,
                    sessionID: model.sessions.selectedSessionID,
                    workingDirectoryPath: chatActions.dependencies.workspaceSettings.defaultWorkingDirectoryPath,
                    onOpenHTMLPreview: { node, root in
                        model.workspaceExplorer.dismissTree()
                        chatActions.dependencies.browser.openLocalHTMLPreview(
                            fileURL: node.url,
                            readAccessRootURL: root.url,
                            preferredSessionID: model.sessions.selectedSessionID
                        )
                    },
                    onClose: model.workspaceExplorer.dismissTree
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(9)
            }

            if let previewModel = model.composer.attachmentPreviewModel {
                AgentAttachmentPreviewOverlay(
                    model: previewModel,
                    onDownloadImage: { chatActions.run.downloadPreviewImage(previewModel) },
                    onShare: { shareAttachment(fileURL: previewModel.sourceFileURL) },
                    onRetryExtraction: { chatActions.composer.retryAttachmentExtraction(attachmentID: previewModel.attachment.id) },
                    onClose: { model.composer.attachmentPreviewModel = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(10)
            }

            if model.workspaceExplorer.isLoadingPreview || model.workspaceExplorer.previewModel != nil {
                WorkspaceFilePreviewOverlay(
                    model: model.workspaceExplorer.previewModel,
                    isLoading: model.workspaceExplorer.isLoadingPreview,
                    onLoadMore: model.workspaceExplorer.loadMorePreview,
                    onCopyFullText: copyWorkspaceFileText,
                    onShare: shareWorkspaceFile,
                    onClose: model.workspaceExplorer.closePreview
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(10)
            }

            if model.sessions.isBackgroundTasksPresented {
                AgentBackgroundTaskOverlay(
                    tasks: chatActions.run.activeSessionBackgroundTasks,
                    onClose: { model.sessions.isBackgroundTasksPresented = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(11)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            chatActions.workspace.openURLInCurrentChatBrowser(url)
            return .handled
        })
    }

    private func shareAttachment(fileURL: URL?) {
        guard let fileURL, AgentAttachmentSharingService.share(fileURL: fileURL) else {
            chatActions.composer.showAttachmentToast(
                title: "分享失败",
                message: "附件原件不存在或当前无法打开系统分享面板。",
                systemImage: "xmark.circle"
            )
            return
        }
    }

    private func shareWorkspaceFile(fileURL: URL) {
        guard AgentAttachmentSharingService.share(fileURL: fileURL) else {
            chatActions.composer.showAttachmentToast(
                title: "分享失败",
                message: "文件不存在或当前无法打开系统分享面板。",
                systemImage: "xmark.circle"
            )
            return
        }
    }

    private func copyWorkspaceFileText(fileURL: URL) {
        Task {
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try WorkspaceFileFullTextReader().read(fileURL: fileURL)
                }.value
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                chatActions.composer.showAttachmentToast(
                    title: "已复制全文",
                    message: "已复制文件内的全部文字。",
                    systemImage: "doc.on.doc"
                )
            } catch {
                chatActions.composer.showAttachmentToast(
                    title: "复制失败",
                    message: "无法读取完整文件文字：\(error.localizedDescription)",
                    systemImage: "xmark.circle"
                )
            }
        }
    }
}

private struct AgentChatToastView: View {
    var toast: AgentChatToast
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            Image(systemName: toast.systemImage)
                .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text(toast.title)
                    .font(AgentChatTypography.metaEmphasis)
                Text(toast.message)
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 420, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.appIcon)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceM)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

private struct AgentAttachmentPreviewOverlay: View {
    var model: AttachmentPreviewModel
    var onDownloadImage: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onRetryExtraction: (() -> Void)? = nil
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label("Attachment", systemImage: "paperclip")
                        .font(AgentChatTypography.meta.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("关闭附件预览")
                    .help("关闭预览")
                }
                .padding(AgentChatLayout.spaceM)

                AgentAttachmentPreviewSheetView(
                    model: model,
                    onDownloadImage: onDownloadImage,
                    onShare: onShare,
                    onRetryExtraction: onRetryExtraction
                )
                    .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.bottom, AgentChatLayout.spaceXL)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentBackgroundTaskOverlay: View {
    var tasks: [AppSessionBackgroundTask]
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label("后台任务", systemImage: "tray.full")
                        .font(AgentChatTypography.meta.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("关闭后台任务")
                    .help("关闭后台任务")
                }
                .padding(AgentChatLayout.spaceM)

                taskContent
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.bottom, AgentChatLayout.spaceXL)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskContent: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView("暂无后台任务", systemImage: "tray", description: Text("当前会话还没有后台任务。"))
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                        ForEach(tasks) { task in
                            taskRow(task)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 260, maxHeight: 460)
            }
        }
    }

    private func taskRow(_ task: AppSessionBackgroundTask) -> some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            statusIcon(for: task)
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title)
                        .font(AgentChatTypography.sectionTitle)
                    Spacer(minLength: AgentChatLayout.spaceS)
                    Text(task.status.displayName)
                        .font(AgentChatTypography.microEmphasis)
                        .foregroundStyle(statusColor(for: task.status))
                }
                Text(task.detail)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let errorMessage = task.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text(task.updatedAt.connorLocalFormatted(date: .none, time: .short))
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusIcon(for task: AppSessionBackgroundTask) -> some View {
        if task.status == .running || task.status == .queued {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: task.status.systemImage)
                .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor(for: task.status))
        }
    }

    private func statusColor(for status: AppSessionBackgroundTaskStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .interrupted: .orange
        }
    }
}

private struct AgentChatSessionListView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions

    var body: some View {
        VStack(spacing: AgentChatLayout.spaceM) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack {
                    Text("会话")
                        .font(AgentChatTypography.sectionTitle)
                    Spacer()
                    Menu {
                        Button(action: { chatActions.session.newChatSession() }) {
                            Label("新建会话", systemImage: "square.and.pencil")
                        }
                        Button(action: { chatActions.session.newNoteSession() }) {
                            Label("新建或导入笔记", systemImage: "note.text.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("新建")

                    Button(action: { chatActions.session.reloadChatSessions() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.borderless)
                    .help("重新加载会话")
                }
                AgentSessionFilterBar(model: model, chatActions: chatActions)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    ForEach(model.sessions.sessions) { session in
                        let row = AgentChatSessionPresentation(session: session)
                        AgentChatSessionRow(
                            row: row,
                            isSelected: session.id == model.sessions.selectedSessionID,
                            hasPendingApproval: model.approvals.hasPendingApproval(sessionID: session.id)
                        ) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                chatActions.session.selectChatSession(session.id)
                            }
                        }
                    }
                }
                .padding(.vertical, AgentChatLayout.spaceXS)
            }

            Spacer(minLength: 0)
        }
        .padding(AgentChatLayout.spaceM)
    }
}

private struct AgentChatSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var hasPendingApproval: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: hasPendingApproval ? "lock.fill" : (row.isFlagged ? "flag.fill" : (isSelected ? "message.fill" : "message")))
                        .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(hasPendingApproval || row.isFlagged ? .orange : (isSelected ? ConnorCraftPalette.accent : .secondary))
                        .frame(width: 16)
                    Text(row.title)
                        .font(isSelected ? AgentChatTypography.sessionTitleEmphasis : AgentChatTypography.sessionTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: AgentChatLayout.spaceS) {
                    AgentStatusPill(status: row.status, text: row.statusText)
                    Text("\(row.messageCount) msgs")
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                    Text(row.relativeUpdatedTime)
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                    if hasPendingApproval {
                        Text("请求审批")
                            .font(AgentChatTypography.micro.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if !row.labels.isEmpty {
                    FlowLikeChips(values: row.labels.map(\.id))
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceM)
            .background(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                    .fill(isSelected ? ConnorCraftPalette.accentSoftFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help(hasPendingApproval ? "当前会话正在等待权限审批，请前往处理" : "")
    }
}

private struct AgentChatConversationView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var imModel: ImFeatureModel?
    @Binding var isSessionInfoPresented: Bool
    @State private var expandedApprovalID: String?
    @State private var lastObservedSessionID: String?
    @State private var lastObservedTranscriptCount: Int = 0
    @State private var visibleMessageLimit: Int = Self.initialVisibleMessageLimit
    @State private var pendingPrependCorrection: PendingPrependCorrection?
    @State private var isLoadingOlderMessages = false
    @State private var selectedForwardMessageIDs: Set<String> = []
    @State private var isForwardSelectionMode = false
    @State private var isForwardSheetPresented = false
    @State private var isForwarding = false
    @StateObject private var chatViewportController = ChatViewportController(
        configuration: ChatViewportConfiguration(
            spacing: AgentChatLayout.chatViewportSpacing,
            bottomPinThreshold: AgentChatLayout.chatBottomPinnedThreshold,
            topLoadTriggerOffset: 96,
            preservesBottomAnchorForUnderfilledContent: true,
            showsJumpToLatestButton: true,
            // The eight-row window bounds eager layout cost and avoids LazyVStack
            // retaining an invalid scroll offset when sessions are replaced.
            contentLayout: .eager
        )
    )

    private static let initialVisibleMessageLimit = 8
    private static let messagePageSize = 8

    private struct PendingPrependCorrection: Equatable {
        var previousFirstItemID: String
        var addedMessageCount: Int
    }

    private var chatViewportConfiguration: ChatViewportConfiguration {
        chatViewportController.configuration
    }

    private var visibleTranscript: [AgentMessage] {
        guard model.run.transcript.count > visibleMessageLimit else { return model.run.transcript }
        return Array(model.run.transcript.suffix(visibleMessageLimit))
    }

    private var hasOlderMessages: Bool {
        visibleMessageLimit < model.run.transcript.count
            || model.run.nextMessageBeforePosition != nil
    }

    private var temporaryAssistantMessageIDs: Set<String> {
        guard model.run.isSubmitting,
              let userIndex = model.run.transcript.lastIndex(where: { $0.role == .user })
        else { return [] }
        return Set(model.run.transcript.suffix(from: model.run.transcript.index(after: userIndex)).compactMap { message in
            message.role == .assistant ? message.id : nil
        })
    }

    private var expandedApproval: AgentPendingApproval? {
        guard let expandedApprovalID else { return nil }
        return chatActions.approval.activeChatPendingApprovals.first { $0.id == expandedApprovalID }
    }

    @ViewBuilder
    private var expandedApprovalOverlay: some View {
        if let approval = expandedApproval {
            AgentPermissionExpandedReviewOverlay(approval: approval, model: model, chatActions: chatActions) {
                expandedApprovalID = nil
            }
            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.985)))
            .zIndex(20)
        }
    }

    @MainActor
    private final class TimelineCache {
        struct TurnCursorKey: Hashable {
            var sessionID: String?
            var transcriptRevision: Int
            var visibleMessageCount: Int
        }

        struct Key: Hashable {
            var sessionID: String?
            var messageCount: Int
            var messageSignature: Int
            var startingTurnCursor: AgentChatTurnCursor
            var contextSignature: Int
            var isSubmitting: Bool
            var preservedOpenProcessState: AgentChatTurnProcessState?
        }

        static let shared = TimelineCache()
        private var entries: [Key: [AgentChatTurnTimelineItem]] = [:]
        private var turnCursors: [TurnCursorKey: AgentChatTurnCursor] = [:]
        private let limit = 24

        func turnCursor(
            key: TurnCursorKey,
            messages: [AgentMessage]
        ) -> AgentChatTurnCursor {
            if let cached = turnCursors[key] { return cached }
            let cursor = AgentChatTurnCursor.beforeVisibleSuffix(
                of: messages,
                visibleCount: key.visibleMessageCount
            )
            if turnCursors.count >= limit {
                turnCursors.removeAll(keepingCapacity: true)
            }
            turnCursors[key] = cursor
            return cursor
        }

        func items(
            key: Key,
            messages: [AgentMessage],
            startingTurnCursor: AgentChatTurnCursor,
            lastContext: AgentContext?,
            isSubmitting: Bool,
            preservedOpenProcessState: AgentChatTurnProcessState?
        ) -> [AgentChatTurnTimelineItem] {
            if let cached = entries[key] { return cached }
            let built = AgentChatTurnTimelineItem.items(
                messages: messages,
                lastContext: lastContext,
                isSubmitting: isSubmitting,
                preservedOpenProcessState: preservedOpenProcessState,
                startingTurnCursor: startingTurnCursor
            )
            if entries.count >= limit {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key] = built
            return built
        }
    }

    private var preservedOpenProcessState: AgentChatTurnProcessState? {
        AgentChatOpenProcessStateResolver.resolve(
            messages: model.run.transcript,
            isSubmitting: model.run.isSubmitting,
            events: model.run.eventTimeline
        )
    }

    private func timelineCacheKey(
        visibleTranscript: [AgentMessage],
        startingTurnCursor: AgentChatTurnCursor
    ) -> TimelineCache.Key {
        let messageSignature = visibleTranscript.reduce(into: 0) { result, message in
            result &+= message.id.hashValue
            result &*= 31
            result &+= message.content.count
            result &*= 31
            result &+= message.citations.count
        }
        let contextSignature = (model.run.lastContext?.query.hashValue ?? 0) ^ (model.run.lastContext?.items.reduce(into: 0) { result, item in
            result &+= item.sourceID.hashValue
            result &*= 31
            result &+= item.content.count
        } ?? 0)
        return TimelineCache.Key(
            sessionID: model.sessions.selectedSessionID,
            messageCount: visibleTranscript.count,
            messageSignature: messageSignature,
            startingTurnCursor: startingTurnCursor,
            contextSignature: contextSignature,
            isSubmitting: model.run.isSubmitting,
            preservedOpenProcessState: preservedOpenProcessState
        )
    }

    private var timelineItems: [AgentChatTurnTimelineItem] {
        let visibleTranscript = visibleTranscript
        let startingTurnCursor = TimelineCache.shared.turnCursor(
            key: TimelineCache.TurnCursorKey(
                sessionID: model.sessions.selectedSessionID,
                transcriptRevision: model.run.transcriptRevision,
                visibleMessageCount: visibleTranscript.count
            ),
            messages: model.run.transcript
        )
        return TimelineCache.shared.items(
            key: timelineCacheKey(
                visibleTranscript: visibleTranscript,
                startingTurnCursor: startingTurnCursor
            ),
            messages: visibleTranscript,
            startingTurnCursor: startingTurnCursor,
            lastContext: model.run.lastContext,
            isSubmitting: model.run.isSubmitting,
            preservedOpenProcessState: preservedOpenProcessState
        )
    }



    private func resetVisibleMessageWindow() {
        visibleMessageLimit = Self.initialVisibleMessageLimit
        pendingPrependCorrection = nil
        isLoadingOlderMessages = false
    }

    private func loadOlderMessagesIfNeeded(firstVisibleItemID: String?, dataSetID: ChatViewportDataSetID) {
        guard !isLoadingOlderMessages,
              hasOlderMessages,
              let firstVisibleItemID
        else { return }

        let previousLimit = visibleMessageLimit
        let nextLimit = min(model.run.transcript.count, previousLimit + Self.messagePageSize)
        let anchorItemID = dataSetID.namespacedElementID(firstVisibleItemID)
        chatViewportController.prepareForPrepend(anchorItemID: anchorItemID)
        if nextLimit > previousLimit {
            isLoadingOlderMessages = true
            pendingPrependCorrection = PendingPrependCorrection(
                previousFirstItemID: anchorItemID,
                addedMessageCount: nextLimit - previousLimit
            )
            visibleMessageLimit = nextLimit
            return
        }

        guard model.run.nextMessageBeforePosition != nil else { return }
        isLoadingOlderMessages = true
        Task { @MainActor in
            let addedCount = await model.run.loadOlderMessages()
            guard addedCount > 0 else {
                isLoadingOlderMessages = false
                return
            }
            pendingPrependCorrection = PendingPrependCorrection(
                previousFirstItemID: anchorItemID,
                addedMessageCount: addedCount
            )
            visibleMessageLimit += addedCount
        }
    }

    private func initialActivityEvents(for process: AgentChatTurnProcessPresentation, latestProcessID: String?) -> [AgentEventPresentation]? {
        let hasLiveBoundary = process.assistantMessageID.map { messageID in
            model.run.eventTimeline.contains { $0.assistantMessageID == messageID }
        } ?? false
        if !model.run.eventTimeline.isEmpty, process.id == latestProcessID || hasLiveBoundary {
            if process.aggregatesRunActivity {
                return AgentAssistantMessageEventSlicer().events(
                    forRunID: process.runID,
                    from: model.run.eventTimeline
                )
            }
            return AgentAssistantMessageEventSlicer().events(
                forAssistantMessageID: process.assistantMessageID,
                from: model.run.eventTimeline
            )
        }
        return nil
    }

    private func loadActivityEvents(for process: AgentChatTurnProcessPresentation, latestProcessID: String?) async -> [AgentEventPresentation] {
        if let initial = initialActivityEvents(for: process, latestProcessID: latestProcessID) {
            return initial
        }
        let restoredEvents = await chatActions.run.restoredAgentEventTimeline(for: process)
        if !restoredEvents.isEmpty {
            return restoredEvents
        }
        return AgentActivityFallbackEvents.events(for: process)
    }

    @ViewBuilder
    private func chatTimelineRow(_ item: AgentChatTurnTimelineItem, latestProcessID: String?) -> some View {
        if let message = item.message {
            VStack(alignment: .leading, spacing: AgentChatLayout.assistantIdentityContentSpacing) {
                if item.showsAssistantHeader, !isNoteBodyMessage(message) {
                    AgentAssistantHeaderView()
                }
                AgentChatMessageRow(
                    row: message,
                    isNoteBody: isNoteBodyMessage(message),
                    allowsAssistantActions: !temporaryAssistantMessageIDs.contains(message.id),
                    persistentCacheContext: chatActions.run.markdownPersistentCacheContext(messageID: message.message.id),
                    localAttachmentFileURL: { attachment in
                        chatActions.composer.localAttachmentFileURL(attachment)
                    },
                    onPreviewAttachment: { attachment in
                        chatActions.composer.previewAttachment(attachment)
                    },
                    onSaveImageAttachment: { attachment in
                        guard let sourceURL = chatActions.composer.localAttachmentFileURL(attachment) else {
                            chatActions.composer.showAttachmentToast(
                                title: "图片另存为失败",
                                message: "图片原件不存在或已不可用。",
                                systemImage: "xmark.circle"
                            )
                            return
                        }
                        chatActions.run.downloadPreviewImage(
                            AttachmentPreviewModel(
                                attachment: attachment,
                                title: attachment.displayName,
                                subtitle: "",
                                body: "",
                                bodyMode: .image,
                                sourceFileURL: sourceURL
                            )
                        )
                    },
                    onShareAttachment: { attachment in
                        shareAttachment(fileURL: chatActions.composer.localAttachmentFileURL(attachment))
                    },
                    onCopyAssistantMessage: { message in
                        chatActions.run.copyAssistantMessageToPasteboard(message)
                    },
                    onExportAssistantMessage: { message in
                        chatActions.run.exportAssistantMessageToFile(message)
                    },
                    onEditNoteBody: noteBodyEditAction(for: message),
                    isForwardSelectionMode: isForwardSelectionMode,
                    isForwardSelected: selectedForwardMessageIDs.contains(message.id),
                    onEnterForwardSelection: {
                        let selectedKind = model.sessions.allSessions.first(where: { $0.id == model.sessions.selectedSessionID })?.governance.kind
                        guard selectedKind != .note, !model.run.isSubmitting else { return }
                        isForwardSelectionMode = true
                        selectedForwardMessageIDs = [message.id]
                    },
                    onToggleForwardSelection: {
                        if selectedForwardMessageIDs.contains(message.id) { selectedForwardMessageIDs.remove(message.id) }
                        else { selectedForwardMessageIDs.insert(message.id) }
                        if selectedForwardMessageIDs.isEmpty { isForwardSelectionMode = false }
                    }
                )
            }
        } else if let process = item.process {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                if item.showsAssistantHeader {
                    AgentAssistantHeaderView()
                }
                AgentChatTurnProcessRow(
                    process: process,
                    isAssistantContinuation: !item.showsAssistantHeader,
                    initialEvents: initialActivityEvents(for: process, latestProcessID: latestProcessID),
                    loadEvents: {
                        await loadActivityEvents(for: process, latestProcessID: latestProcessID)
                    },
                    onOpenToolInvocation: { invocation in
                        model.run.selectedToolInvocation = invocation
                    }
                )
            }
        } else if let timestamp = item.timestamp {
            AgentChatTurnTimestampRow(timestamp: timestamp)
        }
    }

    private func shareAttachment(fileURL: URL?) {
        guard let fileURL, AgentAttachmentSharingService.share(fileURL: fileURL) else {
            chatActions.composer.showAttachmentToast(
                title: "分享失败",
                message: "附件原件不存在或当前无法打开系统分享面板。",
                systemImage: "xmark.circle"
            )
            return
        }
    }

    private func noteBodyEditAction(
        for message: AgentChatMessagePresentation
    ) -> ((String) async -> Bool)? {
        guard isNoteBodyMessage(message), !model.run.isSubmitting else { return nil }
        return { content in
            await chatActions.run.reviseNoteBody(
                messageID: message.message.id,
                expectedContent: message.message.content,
                content: content
            )
        }
    }

    private func isNoteBodyMessage(_ message: AgentChatMessagePresentation) -> Bool {
        guard let sessionID = model.sessions.selectedSessionID else { return false }
        let session = (model.sessions.sessions + model.sessions.allSessions).first { $0.id == sessionID }
        return AgentChatMessagePresentationPolicy.isNoteBody(
            sessionKind: session?.governance.kind,
            firstMessageID: model.run.transcript.first?.id,
            messageID: message.message.id
        )
    }

    private var isNoteModeBeforeFirstMessage: Bool {
        guard let sessionID = model.sessions.selectedSessionID else { return false }
        let session = model.sessions.allSessions.first { $0.id == sessionID }
            ?? model.sessions.sessions.first { $0.id == sessionID }
        return AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: session?.governance.kind,
            sessionMessageCount: session?.messages.count ?? 0,
            persistedMessageCount: model.sessions.messageCountsBySessionID[sessionID],
            transcriptMessageCount: model.run.transcript.count,
            isSubmitting: model.run.isSubmitting
        )
    }

    var body: some View {
        let timelineSnapshot = timelineItems
        let chatItems = AgentChatTimelineAdapter().items(from: timelineSnapshot, insertsDateSeparators: true)
        let latestProcessID = timelineSnapshot.last(where: { $0.process != nil })?.process?.id
        let chatDataSetID = ChatViewportDataSetID.agentChatSession(
            sessionID: model.sessions.selectedSessionID,
            revision: model.run.transcriptRevision
        )
        let noteFullscreen = isNoteModeBeforeFirstMessage

        VStack(spacing: 0) {
            if !noteFullscreen {
                AgentChatConversationHeader(
                    model: model,
                    chatActions: chatActions,
                    isForwardSelectionMode: isForwardSelectionMode,
                    canBeginForwardSelection: canBeginForwardSelection,
                    isSessionInfoPresented: $isSessionInfoPresented,
                    onBeginForwardSelection: {
                        selectedForwardMessageIDs = []
                        isForwardSelectionMode = true
                    }
                )
                    .padding(.horizontal, AgentChatLayout.spaceL)
                    .padding(.top, AgentChatLayout.spaceS)
                    .padding(.bottom, AgentChatLayout.spaceL)
            }

            Group {
                if noteFullscreen {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 0)
                        .clipped()
                        .allowsHitTesting(false)
                } else if model.sessions.isWaitingForSelectedPresentation {
                    AgentChatSessionLoadingView()
                        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                } else if chatItems.isEmpty {
                    AgentChatEmptyStateView()
                        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                } else {
                    CommercialChatViewport(
                        dataSetID: chatDataSetID,
                        items: chatItems,
                        controller: chatViewportController,
                        configuration: chatViewportConfiguration,
                        hasOlderItems: hasOlderMessages,
                        isLoadingOlderItems: isLoadingOlderMessages,
                        onTopReached: {
                            loadOlderMessagesIfNeeded(
                                firstVisibleItemID: AgentChatTimelineAdapter().prependAnchorItemID(in: chatItems),
                                dataSetID: chatDataSetID
                            )
                        }
                    ) { chatItem in
                        Group {
                            if let item = chatItem.timelineItem {
                                chatTimelineRow(item, latestProcessID: latestProcessID)
                            } else if let unreadMarker = chatItem.unreadMarker {
                                AgentChatUnreadMarkerRow(unreadCount: unreadMarker.unreadCount)
                            } else if let dateSeparator = chatItem.dateSeparator {
                                AgentChatDateSeparatorRow(title: dateSeparator.title)
                            }
                        }
                        .padding(.top, spacingAdjustment(for: chatItem.spacingBefore))
                    }
                }
            }
            .padding(.horizontal, noteFullscreen ? 0 : AgentChatLayout.chatViewportHorizontalInset)
            .padding(.vertical, noteFullscreen ? 0 : AgentChatLayout.chatViewportVerticalInset)
            .onAppear {
                // Startup restoration and returning from another workspace can
                // present an already-loaded transcript without a count change.
                // Seed the window from that transcript so it does not stay at
                // the eight-row eager-layout bootstrap limit.
                visibleMessageLimit = max(Self.initialVisibleMessageLimit, model.run.transcript.count)
                pendingPrependCorrection = nil
                isLoadingOlderMessages = false
                lastObservedSessionID = model.sessions.selectedSessionID
                lastObservedTranscriptCount = model.run.transcript.count
            }
            .onChange(of: model.sessions.selectedSessionID) { _, newSessionID in
                resetVisibleMessageWindow()
                lastObservedSessionID = newSessionID
                lastObservedTranscriptCount = model.run.transcript.count
            }
            .onChange(of: model.run.transcript.count) { oldCount, newCount in
                let currentSessionID = model.sessions.selectedSessionID
                defer {
                    lastObservedSessionID = currentSessionID
                    lastObservedTranscriptCount = newCount
                }
                guard currentSessionID == lastObservedSessionID,
                      newCount > oldCount,
                      newCount > lastObservedTranscriptCount
                else { return }
                visibleMessageLimit += newCount - oldCount
                chatViewportController.notifyDataChange(.append(count: newCount - oldCount))
            }
            .onChange(of: visibleMessageLimit) { _, _ in
                guard let pendingPrependCorrection else { return }
                chatViewportController.notifyPrepend(
                    count: pendingPrependCorrection.addedMessageCount,
                    anchorItemID: pendingPrependCorrection.previousFirstItemID
                )
                self.pendingPrependCorrection = nil
                isLoadingOlderMessages = false
            }
            .onChange(of: model.run.isSubmitting) { _, isSubmitting in
                guard isSubmitting else { return }
                chatViewportController.followLatestIfPinned()
            }


            conversationFooter
            .padding(.horizontal, 0)
            .padding(.top, noteFullscreen ? 0 : AgentChatLayout.spaceM)
            .padding(.bottom, noteFullscreen ? 0 : AgentChatLayout.spaceS)
            .layoutPriority(noteFullscreen ? 1 : 0)
        }
        .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .overlay {
            if let invocation = model.run.selectedToolInvocation {
                AgentToolInvocationDetailOverlay(invocation: invocation) {
                    model.run.selectedToolInvocation = nil
                }
                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.985)))
            }
        }
        .overlay {
            expandedApprovalOverlay
        }
        .onChange(of: chatActions.approval.activeChatPendingApprovals.map(\.id)) { _, activeIDs in
            if let expandedApprovalID, !activeIDs.contains(expandedApprovalID) {
                self.expandedApprovalID = nil
            }
        }
        .sheet(isPresented: $isForwardSheetPresented) {
            if let bundle = selectedAgentForwardBundle, let imModel {
                ForwardDestinationSheet(
                    bundle: bundle,
                    pager: imModel.makeForwardDestinationPager(),
                    isSending: isForwarding,
                    onCancel: { isForwardSheetPresented = false },
                    onSend: { caption, destinationKeys in
                        isForwarding = true
                        var outgoing = bundle
                        outgoing.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        do {
                            try await imModel.forward(
                                bundle: outgoing,
                                destinationKeys: destinationKeys,
                                onBackgroundError: { chatActions.errors.errorMessage = $0 }
                            )
                            isForwardSheetPresented = false
                            clearForwardSelection()
                        } catch {
                            chatActions.errors.errorMessage = "转发失败：\(error.localizedDescription)"
                        }
                        isForwarding = false
                    }
                )
            }
        }
        .padding(.horizontal, AgentChatLayout.spaceL)
        .padding(.vertical, AgentChatLayout.spaceM)
    }

    private func spacingAdjustment(for spacing: CommercialChatItemSpacing) -> CGFloat {
        switch spacing {
        case .standard:
            return 0
        case .assistantContinuation:
            return AgentChatLayout.assistantGroupSpacing - AgentChatLayout.chatViewportSpacing
        case .conversationBoundary:
            return AgentChatLayout.conversationTurnSpacing - AgentChatLayout.chatViewportSpacing
        }
    }

    private var selectedAgentForwardBundle: ForwardedChatBundle? {
        guard let sessionID = model.sessions.selectedSessionID,
              let session = model.sessions.allSessions.first(where: { $0.id == sessionID })
        else { return nil }
        let selected = model.run.transcript.filter { selectedForwardMessageIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        return ForwardedChatBundle(
            title: "\(session.title)的聊天记录",
            sourceTitle: session.title,
            items: selected.map { message in
                let nested = ForwardedChatBundleCodec.decode(message.content)
                return ForwardedChatItem(
                    id: message.id,
                    senderName: message.role == .user ? "我" : "康纳",
                    createdAt: Int64(message.createdAt.timeIntervalSince1970 * 1000),
                    kind: nested == nil ? "text" : "forward",
                    text: nested?.title ?? message.content
                )
            }
        )
    }

    @ViewBuilder
    private var conversationFooter: some View {
        if isForwardSelectionMode {
            HStack(spacing: AgentChatLayout.spaceM) {
                Text("已选 \(selectedForwardMessageIDs.count) 条")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("取消") { clearForwardSelection() }
                Button("合并转发", systemImage: "arrowshape.turn.up.right") {
                    isForwardSheetPresented = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedForwardMessageIDs.isEmpty || imModel == nil)
            }
            .padding(.horizontal, AgentChatLayout.spaceL)
            .padding(.vertical, AgentChatLayout.spaceM)
            .background(.bar)
        } else {
            AgentChatComposerView(
                model: model,
                chatActions: chatActions,
                contactsFeatureModel: chatActions.dependencies.contacts,
                onExpandApprovalReview: { approval in
                    expandedApprovalID = approval.id
                }
            )
        }
    }

    private var canBeginForwardSelection: Bool {
        let selectedKind = model.sessions.allSessions
            .first(where: { $0.id == model.sessions.selectedSessionID })?
            .governance.kind
        return selectedKind != .note
            && !model.run.transcript.isEmpty
            && !model.run.isSubmitting
            && imModel != nil
    }

    private func clearForwardSelection() {
        selectedForwardMessageIDs = []
        isForwardSelectionMode = false
    }
}

private struct AgentChatTranscriptContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AgentChatTranscriptViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AgentChatConversationHeader: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var isForwardSelectionMode: Bool
    var canBeginForwardSelection: Bool
    @Binding var isSessionInfoPresented: Bool
    var onBeginForwardSelection: () -> Void
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFocused: Bool

    private var selectedTitle: String {
        selectedSession?.title ?? "智能体聊天"
    }

    private var selectedSession: AgentSession? {
        guard let selectedID = model.sessions.selectedSessionID else { return nil }
        return model.sessions.allSessions.first { $0.id == selectedID }
            ?? model.sessions.sessions.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            ZStack {
                titleView
                    .padding(.horizontal, 220)

                HStack(spacing: AgentChatLayout.spaceS) {
                    Spacer()
                    if !isForwardSelectionMode {
                        Button("选择消息", systemImage: "checkmark.circle") {
                            onBeginForwardSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canBeginForwardSelection)
                        .help("选择多条消息并合并转发")
                    }
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                            isSessionInfoPresented.toggle()
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isSessionInfoPresented ? Color.accentColor : Color.secondary)
                    .help("会话信息")
                    .accessibilityLabel("打开会话信息")
                }
            }

            if let summary = model.run.latestSummary {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Text(summary.content)
                            .font(AgentChatTypography.callout)
                            .textSelection(.enabled)
                        if let freshness = chatActions.run.latestChatSummaryFreshness {
                            Text("覆盖 \(freshness.coveredMessageCount) / \(freshness.currentMessageCount) 条消息 · 更新于 \(summary.updatedAt.connorLocalStandardDateTime())")
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.secondary)
                        }
                        Text(chatActions.run.latestChatSummaryContextMessage)
                            .font(AgentChatTypography.meta)
                            .foregroundColor(chatActions.run.latestChatSummaryFreshness?.isFresh == true ? .secondary : .orange)
                        if let message = model.run.summaryMessage {
                            Text(message)
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, AgentChatLayout.spaceS)
                } label: {
                    Label("会话摘要", systemImage: "text.quote")
                        .font(AgentChatTypography.metaEmphasis)
                }
                .padding(AgentChatLayout.spaceM)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            }
        }
        .onAppear { titleDraft = selectedTitle }
        .onChange(of: selectedTitle) { _, newTitle in
            guard !isEditingTitle else { return }
            titleDraft = newTitle
        }
        .onChange(of: model.sessions.selectedSessionID) { _, _ in
            isEditingTitle = false
            isTitleFocused = false
            titleDraft = selectedTitle
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitleEdit() }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("会话标题", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(AgentChatTypography.title)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .focused($isTitleFocused)
                .onSubmit { commitTitleEdit() }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AgentChatLayout.spaceXL)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
                .onAppear { isTitleFocused = true }
        } else {
            Text(selectedTitle)
                .font(AgentChatTypography.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { beginTitleEdit() }
                .help("单击编辑会话标题")
        }
    }

    private func beginTitleEdit() {
        guard model.sessions.selectedSessionID != nil else { return }
        titleDraft = selectedTitle
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard let selectedID = model.sessions.selectedSessionID, !trimmed.isEmpty, trimmed != selectedTitle else {
            titleDraft = selectedTitle
            return
        }
        chatActions.session.renameChatSession(selectedID, title: trimmed)
    }
}

private struct AgentSessionFilterBar: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            HStack(spacing: AgentChatLayout.spaceS) {
                FilterButton(title: "All", isSelected: model.sessions.filter == .all) { chatActions.session.setSessionListFilter(.all) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                        FilterButton(title: status.displayName, isSelected: model.sessions.filter == .status(status)) {
                            chatActions.session.setSessionListFilter(.status(status))
                        }
                    }
                }
            }
        }
    }
}

private struct FilterButton: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AgentChatTypography.meta.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, AgentChatLayout.spaceM)
                .padding(.vertical, AgentChatLayout.spaceS)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AgentStatusPill: View {
    var status: AgentSessionStatus
    var text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(AgentChatTypography.microEmphasis)
            .padding(.horizontal, AgentChatLayout.spaceS)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var icon: String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle"
        case .blocked: "nosign"
        case .cancelled: "xmark.circle"
        case .archived: "archivebox"
        }
    }

    private var color: Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .blue
        case .waiting: .orange
        case .needsReview: .purple
        case .done: .green
        case .blocked: .red
        case .cancelled: .gray
        case .archived: .gray
        }
    }
}

private struct AgentLabelPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(AgentChatTypography.micro.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, AgentChatLayout.spaceS)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .background(Color.teal.opacity(0.14), in: Capsule())
            .foregroundStyle(.teal)
    }
}

private struct AgentChatInspectorView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    @Binding var isPresented: Bool

    private var selectedSession: AgentSession? {
        guard let selectedID = model.sessions.selectedSessionID else { return nil }
        return model.sessions.allSessions.first { $0.id == selectedID }
            ?? model.sessions.sessions.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
                .padding(.horizontal, AgentChatLayout.spaceL)
                .padding(.top, AgentChatLayout.spaceL)
                .padding(.bottom, AgentChatLayout.spaceM)

            ScrollView {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                    if let session = selectedSession {
                        sessionGovernance(session)
                        labels(session)
                        artifacts
                    } else {
                        ContentUnavailableView("未选择会话", systemImage: "bubble.left.and.bubble.right", description: Text("从会话列表选择一个会话查看信息。"))
                            .frame(minHeight: 240)
                    }
                }
                .padding(.horizontal, AgentChatLayout.spaceL)
                .padding(.bottom, AgentChatLayout.spaceL)
            }
        }
    }

    private var inspectorHeader: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text("信息")
                    .font(AgentChatTypography.sectionTitle)
                Text("会话设置、标签和文件")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AgentChatLayout.spaceM)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                    .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
            }
            .buttonStyle(.plain)
            .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
            .contentShape(Rectangle())
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("关闭信息面板")
        }
    }

    private func sessionGovernance(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Text("会话")
                .font(AgentChatTypography.calloutEmphasis)
            Picker("状态", selection: Binding(
                get: { session.governance.status },
                set: { newValue in
                    DispatchQueue.main.async {
                        chatActions.session.setSelectedSessionStatus(newValue)
                    }
                }
            )) {
                ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: AgentChatLayout.spaceS) {
                Button(session.governance.isFlagged ? "取消标记" : "标记") { chatActions.session.toggleSelectedSessionFlag() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text("消息：\(session.messages.count)")
                Text("更新：\(session.updatedAt.connorLocalStandardDateTime())")
                Text("会话 ID：\(session.id)")
                    .textSelection(.enabled)
            }
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
        }
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
    }

    private func labels(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Text("标签")
                .font(AgentChatTypography.calloutEmphasis)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Text("当前会话标签")
                    .font(AgentChatTypography.metaEmphasis)
                    .foregroundStyle(.secondary)

                if session.governance.labels.isEmpty {
                    Text("暂无已应用标签")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLikeChips(values: session.governance.labels.map { displayText(for: $0) })
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Text("可切换标签")
                    .font(AgentChatTypography.metaEmphasis)
                    .foregroundStyle(.secondary)

                ForEach(chatActions.dependencies.governance.config.labels) { definition in
                    Button {
                        chatActions.session.toggleSelectedSessionLabel(definition.id)
                    } label: {
                        HStack {
                            Image(systemName: session.governance.labels.contains(where: { $0.id == definition.id }) ? "checkmark.circle.fill" : "circle")
                            Text(definition.name)
                            Spacer()
                        }
                        .font(AgentChatTypography.callout)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
    }

    private func displayText(for label: AgentSessionLabel) -> String {
        chatActions.dependencies.governance.config.definition(for: label.id)?.name ?? label.id
    }

    private var artifacts: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text("会话文件")
                .font(AgentChatTypography.calloutEmphasis)
            if let dirs = model.sessions.selectedArtifactDirectories {
                ArtifactPathRow(label: "plans", path: dirs.plans.path)
                ArtifactPathRow(label: "data", path: dirs.data.path)
                ArtifactPathRow(label: "attachments", path: dirs.attachments.path)
                ArtifactPathRow(label: "exports", path: dirs.exports.path)
            } else {
                Text("暂无会话文件。")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
    }
}

private struct ArtifactPathRow: View {
    var label: String
    var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AgentChatTypography.metaEmphasis)
            Text(path)
                .font(AgentChatTypography.monoMicro)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}
