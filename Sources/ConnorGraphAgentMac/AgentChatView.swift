import SwiftUI
import AppKit
import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentChatView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isSessionInfoPresented = false

    var body: some View {
        Group {
            if viewModel.selectedChatSessionID == nil && !viewModel.isBrowserVisible {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                activeSessionContent
            }
        }
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadChatSessionsIfNeededAfterInitialLoad()
                viewModel.reloadPendingApprovals()
            }
        }
    }

    private var activeSessionContent: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if viewModel.isBrowserVisible {
                    BrowserWorkspaceView(viewModel: viewModel)
                } else {
                    AgentChatConversationView(viewModel: viewModel, isSessionInfoPresented: $isSessionInfoPresented)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isSessionInfoPresented {
                AgentChatInspectorView(viewModel: viewModel, isPresented: $isSessionInfoPresented)
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

            if let toast = viewModel.attachmentToast {
                AgentChatToastView(toast: toast) {
                    viewModel.attachmentToast = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(8)
                .padding(.top, AgentChatLayout.spaceL)
                .padding(.trailing, AgentChatLayout.spaceL)
            }

            if let model = viewModel.attachmentPreviewModel {
                AgentAttachmentPreviewOverlay(
                    model: model,
                    onRetryExtraction: { viewModel.retryAttachmentExtraction(attachmentID: model.attachment.id) },
                    onClose: { viewModel.attachmentPreviewModel = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(10)
            }

            if viewModel.isBackgroundTasksPresented {
                AgentBackgroundTaskOverlay(
                    tasks: viewModel.activeSessionBackgroundTasks,
                    onClose: { viewModel.isBackgroundTasksPresented = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(11)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            viewModel.openURLInCurrentChatBrowser(url)
            return .handled
        })
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
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
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

                AgentAttachmentPreviewSheetView(model: model, onRetryExtraction: onRetryExtraction)
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
                    .frame(minHeight: 260)
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
                Text(task.updatedAt.formatted(date: .omitted, time: .shortened))
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
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: AgentChatLayout.spaceM) {
            Button(action: { viewModel.newChatSession() }) {
                SidebarActionButtonLabel(title: "新建对话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack {
                    Text("会话")
                        .font(AgentChatTypography.sectionTitle)
                    Spacer()
                    Button(action: { viewModel.reloadChatSessions() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.borderless)
                    .help("重新加载会话")
                }
                AgentSessionFilterBar(viewModel: viewModel)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    ForEach(viewModel.chatSessions) { session in
                        let row = AgentChatSessionPresentation(session: session)
                        AgentChatSessionRow(
                            row: row,
                            isSelected: session.id == viewModel.selectedChatSessionID
                        ) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                viewModel.selectChatSession(session.id)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: row.isFlagged ? "flag.fill" : (isSelected ? "message.fill" : "message"))
                        .font(.system(size: AgentChatTypography.controlIconSize, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(row.isFlagged ? .orange : (isSelected ? ConnorCraftPalette.accent : .secondary))
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
                }
                if !row.labels.isEmpty {
                    FlowLikeChips(values: row.labels.prefix(3).map(\.id))
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
    }
}

private struct AgentChatConversationView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isSessionInfoPresented: Bool
    @State private var activityDetailEvent: AgentEventPresentation?
    @State private var selectedToolInvocation: AgentToolInvocationPresentation?
    @State private var lastObservedSessionID: String?
    @State private var lastObservedTranscriptCount: Int = 0
    @State private var pendingSessionTranscriptReloadID: String?
    @State private var transcriptContentHeight: CGFloat = 0
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var transcriptScrollResetID = UUID()
    private let collapseScrollPolicy = AgentChatCollapseScrollPolicy()
    private let transcriptTopAnchorID = "agent-chat-transcript-top-anchor"

    @MainActor
    private final class TimelineCache {
        struct Key: Hashable {
            var sessionID: String?
            var messageCount: Int
            var messageSignature: Int
            var contextSignature: Int
            var isSubmitting: Bool
            var preservesOpenProcess: Bool
        }

        static let shared = TimelineCache()
        private var entries: [Key: [AgentChatTurnTimelineItem]] = [:]
        private let limit = 24

        func items(
            key: Key,
            messages: [AgentMessage],
            lastContext: AgentContext?,
            isSubmitting: Bool,
            preservesOpenProcess: Bool
        ) -> [AgentChatTurnTimelineItem] {
            if let cached = entries[key] { return cached }
            let built = AgentChatTurnTimelineItem.items(
                messages: messages,
                lastContext: lastContext,
                isSubmitting: isSubmitting,
                preservesOpenProcess: preservesOpenProcess
            )
            if entries.count >= limit {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key] = built
            return built
        }
    }

    private var shouldPreserveOpenProcess: Bool {
        guard !viewModel.isSubmittingChat,
              !viewModel.agentEventTimeline.isEmpty,
              viewModel.transcript.last?.role == .user
        else { return false }
        return true
    }

    private var timelineCacheKey: TimelineCache.Key {
        let messageSignature = viewModel.transcript.reduce(into: 0) { result, message in
            result &+= message.id.hashValue
            result &*= 31
            result &+= message.content.count
            result &*= 31
            result &+= message.citations.count
        }
        let contextSignature = (viewModel.lastContext?.query.hashValue ?? 0) ^ (viewModel.lastContext?.items.reduce(into: 0) { result, item in
            result &+= item.sourceID.hashValue
            result &*= 31
            result &+= item.content.count
        } ?? 0)
        return TimelineCache.Key(
            sessionID: viewModel.selectedChatSessionID,
            messageCount: viewModel.transcript.count,
            messageSignature: messageSignature,
            contextSignature: contextSignature,
            isSubmitting: viewModel.isSubmittingChat,
            preservesOpenProcess: shouldPreserveOpenProcess
        )
    }

    private var timelineItems: [AgentChatTurnTimelineItem] {
        TimelineCache.shared.items(
            key: timelineCacheKey,
            messages: viewModel.transcript,
            lastContext: viewModel.lastContext,
            isSubmitting: viewModel.isSubmittingChat,
            preservesOpenProcess: shouldPreserveOpenProcess
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let targetID = timelineItems.last?.id
        guard let targetID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(transcriptTopAnchorID, anchor: .top)
        }
    }

    private func scrollAfterSessionSwitchLayout(proxy: ScrollViewProxy, sessionID: String?) {
        scheduleScrollDecisionAfterLayout(proxy: proxy) {
            guard sessionID == viewModel.selectedChatSessionID else { return .doNotScroll }
            let contentHeight = Double(self.transcriptContentHeight)
            let viewportHeight = Double(self.transcriptViewportHeight)
            let dimensionsReady = contentHeight.isFinite && viewportHeight.isFinite && contentHeight > 0 && viewportHeight > 0
            // Dimensions not yet measured → try scrolling (next probe will retry if it fails)
            guard dimensionsReady else { return .scrollToBottom }
            // Content fits viewport → no scroll needed (avoids white screen)
            guard contentHeight > viewportHeight + 1 else { return .doNotScroll }
            // Content overflows → scroll to latest messages
            return .scrollToBottom
        }
    }

    private func scheduleScrollDecisionAfterLayout(
        proxy: ScrollViewProxy,
        decision: @escaping () -> AgentChatCollapseScrollPolicy.Decision
    ) {
        for delay in AgentChatCollapseScrollSchedule.decisionDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch decision() {
                case .scrollToTop:
                    scrollToTop(proxy: proxy)
                case .scrollToBottom:
                    scrollToBottom(proxy: proxy)
                case .doNotScroll:
                    return
                }
            }
        }
    }

    private func activityEvents(for process: AgentChatTurnProcessPresentation, latestProcessID: String?) -> [AgentEventPresentation] {
        if process.id == latestProcessID, !viewModel.agentEventTimeline.isEmpty {
            return viewModel.agentEventTimeline
        }
        let restoredEvents = viewModel.restoredAgentEventTimeline(for: process)
        if !restoredEvents.isEmpty {
            return restoredEvents
        }
        return AgentActivityFallbackEvents.events(for: process)
    }

    var body: some View {
        let timelineSnapshot = timelineItems
        let latestProcessID = timelineSnapshot.last(where: { $0.process != nil })?.process?.id

        VStack(spacing: 0) {
            AgentChatConversationHeader(viewModel: viewModel)
                .padding(.horizontal, AgentChatLayout.spaceL)
                .padding(.top, AgentChatLayout.spaceS)
                .padding(.bottom, AgentChatLayout.spaceL)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                        Color.clear
                            .frame(height: 0)
                            .id(transcriptTopAnchorID)

                        if timelineSnapshot.isEmpty {
                            AgentChatEmptyStateView()
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ForEach(timelineSnapshot) { item in
                                if let message = item.message {
                                    AgentChatMessageRow(
                                        row: message,
                                        persistentCacheContext: viewModel.markdownPersistentCacheContext(messageID: message.message.id),
                                        onPreviewAttachment: { attachment in
                                            viewModel.previewAttachment(attachment)
                                        }
                                    )
                                    .id(item.id)
                                } else if let process = item.process {
                                    AgentChatTurnProcessRow(
                                        process: process,
                                        events: activityEvents(for: process, latestProcessID: latestProcessID),
                                        onOpenDetail: { event in
                                            activityDetailEvent = event
                                        },
                                        onOpenToolInvocation: { invocation in
                                            selectedToolInvocation = invocation
                                        }
                                    )
                                    .id(item.id)
                                } else if let timestamp = item.timestamp {
                                    AgentChatTurnTimestampRow(timestamp: timestamp)
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 0)
                    .padding(.vertical, AgentChatLayout.spaceXL)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: AgentChatTranscriptContentHeightKey.self, value: geometry.size.height)
                        }
                    )
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: AgentChatTranscriptViewportHeightKey.self, value: geometry.size.height)
                    }
                )
                .id(transcriptScrollResetID)
                .onPreferenceChange(AgentChatTranscriptContentHeightKey.self) { height in
                    transcriptContentHeight = height
                }
                .onPreferenceChange(AgentChatTranscriptViewportHeightKey.self) { height in
                    transcriptViewportHeight = height
                }
                .onAppear {
                    lastObservedSessionID = viewModel.selectedChatSessionID
                    lastObservedTranscriptCount = viewModel.transcript.count
                }
                .onChange(of: viewModel.selectedChatSessionID) { _, newSessionID in
                    pendingSessionTranscriptReloadID = newSessionID
                    lastObservedSessionID = newSessionID
                    lastObservedTranscriptCount = viewModel.transcript.count
                }
                .onChange(of: viewModel.transcript.count) { oldCount, newCount in
                    let currentSessionID = viewModel.selectedChatSessionID
                    defer {
                        lastObservedSessionID = currentSessionID
                        lastObservedTranscriptCount = newCount
                    }
                    if pendingSessionTranscriptReloadID == currentSessionID {
                        pendingSessionTranscriptReloadID = nil
                        scrollAfterSessionSwitchLayout(proxy: proxy, sessionID: currentSessionID)
                        return
                    }
                    guard currentSessionID == lastObservedSessionID,
                          newCount > oldCount,
                          newCount > lastObservedTranscriptCount
                    else { return }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isSubmittingChat) { _, isSubmitting in
                    guard isSubmitting else { return }
                    scrollToBottom(proxy: proxy)
                }

                AgentChatComposerView(
                    viewModel: viewModel,
                    isSessionInfoPresented: $isSessionInfoPresented
                )
                .padding(.horizontal, 0)
                .padding(.vertical, AgentChatLayout.spaceM)
            }
        }
        .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .overlay {
            if let event = activityDetailEvent, selectedToolInvocation == nil {
                AgentActivityDetailOverlay(event: event) {
                    activityDetailEvent = nil
                }
                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.985)))
            }
        }
        .overlay {
            if let invocation = selectedToolInvocation {
                AgentToolInvocationDetailOverlay(invocation: invocation) {
                    selectedToolInvocation = nil
                }
                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.985)))
            }
        }
        .padding(.horizontal, AgentChatLayout.spaceL)
        .padding(.vertical, AgentChatLayout.spaceM)
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
    @ObservedObject var viewModel: AppViewModel
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFocused: Bool

    private var selectedTitle: String {
        selectedSession?.title ?? "智能体聊天"
    }

    private var selectedSession: AgentSession? {
        guard let selectedID = viewModel.selectedChatSessionID else { return nil }
        return viewModel.allChatSessions.first { $0.id == selectedID }
            ?? viewModel.chatSessions.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            titleView

            if let summary = viewModel.latestChatSummary {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Text(summary.content)
                            .font(AgentChatTypography.callout)
                            .textSelection(.enabled)
                        if let freshness = viewModel.latestChatSummaryFreshness {
                            Text("覆盖 \(freshness.coveredMessageCount) / \(freshness.currentMessageCount) 条消息 · 更新于 \(summary.updatedAt.formatted())")
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.latestChatSummaryContextMessage)
                            .font(AgentChatTypography.meta)
                            .foregroundColor(viewModel.latestChatSummaryFreshness?.isFresh == true ? .secondary : .orange)
                        if let message = viewModel.chatSummaryMessage {
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
        .onChange(of: viewModel.selectedChatSessionID) { _, _ in
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
        guard viewModel.selectedChatSessionID != nil else { return }
        titleDraft = selectedTitle
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard let selectedID = viewModel.selectedChatSessionID, !trimmed.isEmpty, trimmed != selectedTitle else {
            titleDraft = selectedTitle
            return
        }
        viewModel.renameChatSession(selectedID, title: trimmed)
    }
}

private struct AgentSessionFilterBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            HStack(spacing: AgentChatLayout.spaceS) {
                FilterButton(title: "All", isSelected: viewModel.sessionListFilter == .all) { viewModel.setSessionListFilter(.all) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                        FilterButton(title: status.displayName, isSelected: viewModel.sessionListFilter == .status(status)) {
                            viewModel.setSessionListFilter(.status(status))
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
    @ObservedObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    private var selectedSession: AgentSession? {
        guard let selectedID = viewModel.selectedChatSessionID else { return nil }
        return viewModel.allChatSessions.first { $0.id == selectedID }
            ?? viewModel.chatSessions.first { $0.id == selectedID }
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
                    viewModel.deferViewUpdate {
                        viewModel.setSelectedSessionStatus(newValue)
                    }
                }
            )) {
                ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: AgentChatLayout.spaceS) {
                Button(session.governance.isFlagged ? "取消标记" : "标记") { viewModel.toggleSelectedSessionFlag() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text("消息：\(session.messages.count)")
                Text("更新：\(session.updatedAt.formatted())")
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

                ForEach(viewModel.governanceConfig.labels) { definition in
                    Button {
                        viewModel.toggleSelectedSessionLabel(definition.id)
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
        viewModel.governanceConfig.definition(for: label.id)?.name ?? label.id
    }

    private var artifacts: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text("会话文件")
                .font(AgentChatTypography.calloutEmphasis)
            if let dirs = viewModel.selectedSessionArtifactDirectories {
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

