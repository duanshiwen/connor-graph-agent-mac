import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

private enum AgentChatLayout {
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
    static let radiusXL: CGFloat = 20

    static let hairlineOpacity: Double = 0.14
    static let chipHeight: CGFloat = 28
    static let iconButtonSize: CGFloat = 28
    static let primaryButtonSize: CGFloat = 32
    static let composerTextMinHeight: CGFloat = 52
    static let composerTextMaxHeight: CGFloat = 132
    static let composerInfoButtonWidth: CGFloat = 88
    static let modelMenuMaxWidth: CGFloat = 190

    static let messageMaxWidth: CGFloat = 760
    static let userMessageMaxWidth: CGFloat = 560
    static let processMaxWidth: CGFloat = 700
    static let messageSideInset: CGFloat = 80
}

struct AgentChatView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isSessionInfoPresented = false

    var body: some View {
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
                AgentChatInspectorView(viewModel: viewModel)
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
        }
        .navigationTitle("Connor Sessions")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadChatSessions()
                viewModel.reloadPendingApprovals()
            }
        }
    }
}

private struct AgentChatSessionListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: AgentChatLayout.spaceM) {
            Button(action: { viewModel.newChatSession() }) {
                Label("新建对话", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack {
                    Text("Inbox")
                        .font(.headline)
                    Spacer()
                    Button(action: { viewModel.reloadChatSessions() }) {
                        Image(systemName: "arrow.clockwise")
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
                            viewModel.selectChatSession(session.id)
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
                        .font(.caption)
                        .foregroundStyle(row.isFlagged ? .orange : (isSelected ? .accentColor : .secondary))
                        .frame(width: 16)
                    Text(row.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: AgentChatLayout.spaceS) {
                    AgentStatusPill(status: row.status, text: row.statusText)
                    Text("\(row.messageCount) msgs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(row.relativeUpdatedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !row.labels.isEmpty {
                    FlowLikeChips(values: row.labels.prefix(3).map(\.displayText))
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceM)
            .background(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentChatConversationView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isSessionInfoPresented: Bool

    private var timelineItems: [AgentChatTurnTimelineItem] {
        AgentChatTurnTimelineItem.items(
            messages: viewModel.transcript,
            lastContext: viewModel.lastContext,
            isSubmitting: viewModel.isSubmittingChat
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let targetID = timelineItems.last?.id
        guard let targetID else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentChatConversationHeader(viewModel: viewModel)
                .padding(.horizontal, AgentChatLayout.spaceL)
                .padding(.vertical, AgentChatLayout.spaceM)

            if !viewModel.agentEventTimeline.isEmpty {
                AgentEventTimelineView(events: viewModel.agentEventTimeline)
                    .padding(.horizontal, AgentChatLayout.spaceL)
                    .padding(.bottom, AgentChatLayout.spaceS)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                        if timelineItems.isEmpty {
                            AgentChatEmptyStateView()
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ForEach(timelineItems) { item in
                                if let message = item.message {
                                    AgentChatMessageRow(row: message)
                                        .id(item.id)
                                } else if let process = item.process {
                                    AgentChatTurnProcessRow(process: process)
                                        .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.vertical, AgentChatLayout.spaceXL)
                }
                .onChange(of: viewModel.transcript.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isSubmittingChat) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            AgentChatComposerView(viewModel: viewModel, isSessionInfoPresented: $isSessionInfoPresented)
                .padding(.horizontal, AgentChatLayout.spaceL)
                .padding(.vertical, AgentChatLayout.spaceM)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
    }
}

private struct AgentChatConversationHeader: View {
    @ObservedObject var viewModel: AppViewModel

    private var selectedTitle: String {
        viewModel.chatSessions.first(where: { $0.id == viewModel.selectedChatSessionID })?.title ?? "智能体聊天"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            HStack(spacing: AgentChatLayout.spaceM) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    Text(selectedTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: AgentChatLayout.spaceS) {
                        if let session = viewModel.chatSessions.first(where: { $0.id == viewModel.selectedChatSessionID }) {
                            AgentStatusPill(status: session.governance.status, text: session.governance.status.displayName)
                            ForEach(session.governance.labels.prefix(4)) { label in
                                AgentLabelPill(text: label.displayText)
                            }
                        }
                        Text("图谱增强对话工作区")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("重新加载") { viewModel.reloadChatSessions() }
                Button(viewModel.summarizeChatSessionButtonTitle) {
                    Task { await viewModel.summarizeSelectedChatSession() }
                }
                .disabled(!viewModel.canSummarizeSelectedChatSession)
            }

            if let summary = viewModel.latestChatSummary {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Text(summary.content)
                            .font(.subheadline)
                            .textSelection(.enabled)
                        if let freshness = viewModel.latestChatSummaryFreshness {
                            Text("覆盖 \(freshness.coveredMessageCount) / \(freshness.currentMessageCount) 条消息 · 更新于 \(summary.updatedAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.latestChatSummaryContextMessage)
                            .font(.caption)
                            .foregroundColor(viewModel.latestChatSummaryFreshness?.isFresh == true ? .secondary : .orange)
                        if let message = viewModel.chatSummaryMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, AgentChatLayout.spaceS)
                } label: {
                    Label("会话摘要", systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                }
                .padding(AgentChatLayout.spaceM)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            }
        }
    }
}

private struct AgentEventTimelineView: View {
    var events: [AgentEventPresentation]

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            HStack(spacing: AgentChatLayout.spaceS) {
                                Image(systemName: icon(for: event.severity))
                                    .foregroundStyle(color(for: event.severity))
                                Text(event.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            Text(event.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .frame(width: 220, alignment: .leading)
                            Text(event.kind)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(AgentChatLayout.spaceM)
                        .frame(width: 250, alignment: .leading)
                        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                                .stroke(color(for: event.severity).opacity(0.28), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Agent 运行时间线（\(events.count) 个事件）", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
        }
    }

    private func icon(for severity: AgentEventPresentationSeverity) -> String {
        switch severity {
        case .info: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: AgentEventPresentationSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private struct AgentChatEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("开始基于图谱的对话")
                .font(.title3.weight(.semibold))
            Text("你可以询问已导入的图谱知识。每一轮助手回复都可以展开查看提示词、上下文、Token 预算和引用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentChatMessageRow: View {
    var row: AgentChatMessagePresentation

    private var isUser: Bool { row.message.role == .user }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: AgentChatLayout.messageSideInset) }

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Text(row.roleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUser ? .white.opacity(0.90) : .secondary)
                    Text("第 \(row.turnNumber) 轮")
                        .font(.caption2)
                        .foregroundStyle(isUser ? .white.opacity(0.65) : .secondary)
                    Text(row.message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isUser ? .white.opacity(0.65) : .secondary)
                }

                Text(row.message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: isUser ? AgentChatLayout.userMessageMaxWidth : AgentChatLayout.messageMaxWidth, alignment: .leading)
            .background(messageBackground, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(isUser ? Color.clear : Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )

            if !isUser { Spacer(minLength: AgentChatLayout.messageSideInset) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var messageBackground: Color {
        if isUser { return Color.accentColor.opacity(0.88) }
        return Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }
}

private struct AgentChatTurnProcessRow: View {
    var process: AgentChatTurnProcessPresentation

    var body: some View {
        HStack(alignment: .top) {
            Spacer(minLength: AgentChatLayout.messageSideInset)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: process.state == .running ? "clock.arrow.circlepath" : "checkmark.circle")
                        .foregroundStyle(process.state == .running ? .orange : .secondary)
                    Text(process.title)
                        .font(.caption.weight(.semibold))
                    if process.state == .running {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: "info.circle")
                    Text(process.summary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AgentChatLayout.spaceS)
                .padding(.vertical, AgentChatLayout.spaceS)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))

                if process.state == .running {
                    ThinkingDotsView()
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                        if process.state == .running {
                            Label("正在准备图谱上下文和提示词", systemImage: "magnifyingglass")
                            Label("正在组装近期对话和可选会话摘要", systemImage: "text.bubble")
                            Label("正在调用已配置的模型提供方", systemImage: "network")
                        }

                        Text("这里展示的是本轮调用前真实可见的会话历史，以及本轮提示词快照；其中“对话上下文”只代表发送给模型的近期消息数量，不等于完整历史。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let request = process.currentRequest {
                            MetadataBlock(title: "本轮用户输入", text: request)
                        }

                        if !process.conversationHistory.isEmpty {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                                Text("完整对话历史（截至本轮回复前 \(process.fullConversationMessageCount) 条）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(process.conversationHistory) { historyRow in
                                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                                        HStack(spacing: AgentChatLayout.spaceS) {
                                            Text(historyRow.roleLabel)
                                                .font(.caption.weight(.semibold))
                                            Text("第 \(historyRow.turnNumber) 轮")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(historyRow.message.createdAt.formatted(date: .omitted, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(historyRow.message.content)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }

                        if !process.citationIDs.isEmpty {
                            MetadataChips(title: "本轮使用的引用", values: process.citationIDs)
                        }

                        if !process.expandedContextItems.isEmpty {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                                Text("使用的图谱上下文")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(process.expandedContextItems) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.sourceID)
                                            .font(.caption.weight(.semibold))
                                        Text(item.content)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }

                        if let prompt = process.promptSnapshotText, !prompt.isEmpty {
                            MetadataBlock(title: "提示词快照", text: prompt, monospaced: true)
                        } else if process.state == .completed {
                            Text("本轮没有保存渲染后的提示词快照。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                } label: {
                    Text(process.state == .running ? "处理详情" : "轮次详情")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: AgentChatLayout.processMaxWidth, alignment: .leading)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )

            Spacer(minLength: AgentChatLayout.messageSideInset)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AgentChatPendingAssistantRow: View {
    var pending: AgentChatPendingAssistantPresentation

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Text("助手")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("第 \(pending.turnNumber) 轮")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                    Text(pending.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ThinkingDotsView()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Label(pending.processingSummary, systemImage: "magnifyingglass")
                        Label("正在组装近期对话和可选会话摘要", systemImage: "text.bubble")
                        Label("正在调用已配置的模型提供方", systemImage: "network")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                } label: {
                    Text("处理中")
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: AgentChatLayout.messageMaxWidth, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )

            Spacer(minLength: AgentChatLayout.messageSideInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingDotsView: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.65))
                    .frame(width: 6, height: 6)
                    .opacity(index == 0 ? 1.0 : 0.45)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.18), in: Capsule())
    }
}

private struct AgentChatTurnInspectorView: View {
    var row: AgentChatMessagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if let summary = row.turnMetadataSummary {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: "info.circle")
                    Text(summary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                    if let request = row.currentRequest {
                        MetadataBlock(title: "当前请求", text: request)
                    }

                    if !row.citationIDs.isEmpty {
                        MetadataChips(title: "引用", values: row.citationIDs)
                    }

                    if !row.expandedContextItems.isEmpty {
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            Text("引用的图谱上下文")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(row.expandedContextItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.sourceID)
                                        .font(.caption.weight(.semibold))
                                    Text(item.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    if let prompt = row.promptSnapshotText, !prompt.isEmpty {
                        MetadataBlock(title: "提示词快照", text: prompt, monospaced: true)
                    } else if row.message.promptInspection != nil {
                        Text("本轮没有保存渲染后的提示词快照。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("轮次信息")
                    .font(.caption.weight(.semibold))
            }
            .font(.caption)
        }
    }
}

private struct MetadataBlock: View {
    var title: String
    var text: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MetadataChips: View {
    var title: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLikeChips(values: values)
        }
    }
}

private struct FlowLikeChips: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct AgentChatPermissionRequestCard: View {
    var approval: AgentPendingApproval
    @ObservedObject var viewModel: AppViewModel
    @State private var isPayloadExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.orange)
                    .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)

                VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    HStack(spacing: AgentChatLayout.spaceS) {
                        Text("需要权限")
                            .font(.subheadline.weight(.semibold))
                        Text(approval.capability.rawValue)
                            .font(.caption.monospaced())
                            .padding(.horizontal, AgentChatLayout.spaceS)
                            .padding(.vertical, AgentChatLayout.spaceXS)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    if let toolName = approval.toolName, !toolName.isEmpty {
                        Label("Tool: \(toolName)", systemImage: "wrench.and.screwdriver")
                    } else {
                        Label("Request: \(approval.requestID)", systemImage: "number")
                    }

                    Label("Session: \(approval.sessionID)", systemImage: "bubble.left.and.bubble.right")

                    DisclosureGroup(isExpanded: $isPayloadExpanded) {
                        Text(approval.payloadJSON)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(isPayloadExpanded ? nil : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AgentChatLayout.spaceM)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                    } label: {
                        Text(compactPayload)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .padding(.horizontal, AgentChatLayout.spaceM)
                            .frame(height: AgentChatLayout.chipHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: AgentChatLayout.spaceS) {
                Button {
                    viewModel.approvePendingApproval(approval)
                } label: {
                    Label("Allow", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    viewModel.alwaysAllowPendingApproval(approval)
                } label: {
                    Label("Always Allow", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("将当前 Sidecar 会话权限提升为受信写入，并批准这个请求")

                Button(role: .destructive) {
                    viewModel.denyPendingApproval(approval)
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: AgentChatLayout.spaceS)

                Text("Always Allow 会记住当前会话权限模式")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var compactPayload: String {
        let trimmed = approval.payloadJSON
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{}" : trimmed
    }
}

private struct AgentChatComposerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isSessionInfoPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if let approval = viewModel.activeChatPendingApprovals.first {
                AgentChatPermissionRequestCard(approval: approval, viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ZStack(alignment: .topTrailing) {
                SafeChatComposerTextView(
                    text: $viewModel.chatInput,
                    placeholder: "按 Shift + Return 换行",
                    isSpellCheckEnabled: viewModel.spellCheckEnabled,
                    onSubmit: { Task { await viewModel.submitChat() } }
                )
                .padding(.leading, AgentChatLayout.spaceM)
                .padding(.trailing, AgentChatLayout.composerInfoButtonWidth)
                .padding(.vertical, AgentChatLayout.spaceM)
                .frame(minHeight: AgentChatLayout.composerTextMinHeight, maxHeight: AgentChatLayout.composerTextMaxHeight, alignment: .topLeading)

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        isSessionInfoPresented.toggle()
                    }
                } label: {
                    Label("信息", systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceM)
                        .frame(height: AgentChatLayout.chipHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("会话信息")
                .padding(.top, AgentChatLayout.spaceS)
                .padding(.trailing, AgentChatLayout.spaceS)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )

            HStack(spacing: AgentChatLayout.spaceS) {
                Button(action: {}) {
                    Image(systemName: "paperclip")
                        .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                }
                .buttonStyle(.plain)
                .help("添加附件")

                Button(action: { viewModel.isBrowserVisible.toggle() }) {
                    Label(viewModel.isBrowserVisible ? "隐藏浏览器" : "浏览器", systemImage: "safari")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceM)
                        .frame(height: AgentChatLayout.chipHeight)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let inspection = viewModel.lastPromptInspection {
                    Label("约 \(inspection.estimatedPromptTokenCount) tokens", systemImage: "text.alignleft")
                        .font(.caption2)
                        .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
                }

                Spacer(minLength: AgentChatLayout.spaceS)

                Picker("权限", selection: $viewModel.sidecarPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 116)
                .controlSize(.small)
                .help("调整本轮会话权限")

                modelSelectionMenu

                Button(action: { Task { await viewModel.submitChat() } }) {
                    Image(systemName: viewModel.isSubmittingChat ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: AgentChatLayout.primaryButtonSize, height: AgentChatLayout.primaryButtonSize)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingChat)
            }
            .frame(minHeight: AgentChatLayout.primaryButtonSize)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
        )
    }

    private var modelSelectionMenu: some View {
        Menu {
            if viewModel.isLoadingLLMModelConnections {
                Label("正在加载模型列表…", systemImage: "arrow.triangle.2.circlepath")
            }

            if viewModel.llmModelConnections.isEmpty {
                Button(viewModel.llmSelectedModel.isEmpty ? "未选择模型" : viewModel.llmSelectedModel) {}
                    .disabled(true)
            } else {
                ForEach(viewModel.llmModelConnections) { connection in
                    Menu {
                        if connection.models.isEmpty {
                            Button("没有可用模型") {}
                                .disabled(true)
                        } else {
                            ForEach(connection.models) { model in
                                Button {
                                    viewModel.selectLLMModel(model.id, providerMode: connection.providerMode)
                                } label: {
                                    if model.id == viewModel.llmSelectedModel && connection.providerMode == viewModel.llmProviderMode {
                                        Label(model.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(model.displayName)
                                    }
                                }
                                .help(model.id)
                            }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                                Text(connection.title)
                                Text(connection.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: connection.isLiveCatalog ? "network" : "bolt.horizontal.circle")
                        }
                    }
                }

                Divider()

                Button {
                    Task { await viewModel.reloadLLMModelConnections() }
                } label: {
                    Label("刷新模型列表", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            Label {
                Text(viewModel.llmSelectedModel.isEmpty ? "未选择模型" : viewModel.llmSelectedModel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "cpu")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, AgentChatLayout.spaceM)
            .frame(height: AgentChatLayout.chipHeight)
            .frame(maxWidth: AgentChatLayout.modelMenuMaxWidth)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help("选择真实配置的连接和模型；切换后下一轮请求立即使用该模型")
    }

    private func promptBudgetStatusColor(_ status: AgentPromptBudgetStatus) -> Color {
        switch status {
        case .safe: return .secondary
        case .warning: return .orange
        case .over: return .red
        }
    }
}

private struct AgentSessionFilterBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            HStack(spacing: AgentChatLayout.spaceS) {
                FilterButton(title: "Inbox", isSelected: viewModel.sessionListFilter == .inbox) { viewModel.setSessionListFilter(.inbox) }
                FilterButton(title: "All", isSelected: viewModel.sessionListFilter == .all) { viewModel.setSessionListFilter(.all) }
                FilterButton(title: "Archive", isSelected: viewModel.sessionListFilter == .archived) { viewModel.setSessionListFilter(.archived) }
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
                .font(.caption.weight(isSelected ? .semibold : .regular))
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
            .font(.caption2.weight(.semibold))
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
        case .archived: .gray
        }
    }
}

private struct AgentLabelPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, AgentChatLayout.spaceS)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .background(Color.teal.opacity(0.14), in: Capsule())
            .foregroundStyle(.teal)
    }
}

private struct AgentChatInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    private var selectedSession: AgentSession? {
        viewModel.chatSessions.first { $0.id == viewModel.selectedChatSessionID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    Text("信息")
                        .font(.headline)
                    Text("会话设置、标签和文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let session = selectedSession {
                    sessionGovernance(session)
                    labels(session)
                    artifacts
                } else {
                    ContentUnavailableView("未选择会话", systemImage: "bubble.left.and.bubble.right", description: Text("从会话列表选择一个会话查看信息。"))
                        .frame(minHeight: 240)
                }
            }
            .padding(AgentChatLayout.spaceL)
        }
    }

    private func sessionGovernance(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Text("会话")
                .font(.subheadline.weight(.semibold))
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
                if session.governance.isArchived {
                    Button("恢复") { viewModel.restoreSelectedSession() }
                } else {
                    Button("归档") { viewModel.archiveSelectedSession() }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text("消息：\(session.messages.count)")
                Text("更新：\(session.updatedAt.formatted())")
                Text("会话 ID：\(session.id)")
                    .textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
    }

    private func labels(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Text("标签")
                .font(.subheadline.weight(.semibold))
            ForEach(viewModel.governanceConfig.labels.filter { $0.valueType == .boolean }) { definition in
                Button {
                    viewModel.toggleSelectedSessionLabel(definition.id)
                } label: {
                    HStack {
                        Image(systemName: session.governance.labels.contains(where: { $0.id == definition.id }) ? "checkmark.circle.fill" : "circle")
                        Text(definition.name)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
    }

    private var artifacts: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text("会话文件")
                .font(.subheadline.weight(.semibold))
            if let dirs = viewModel.selectedSessionArtifactDirectories {
                ArtifactPathRow(label: "plans", path: dirs.plans.path)
                ArtifactPathRow(label: "data", path: dirs.data.path)
                ArtifactPathRow(label: "attachments", path: dirs.attachments.path)
                ArtifactPathRow(label: "exports", path: dirs.exports.path)
            } else {
                Text("暂无会话文件。")
                    .font(.caption)
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
                .font(.caption.weight(.semibold))
            Text(path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct SafeChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSpellCheckEnabled: Bool
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder
        if textView.string != text {
            textView.string = text
        }
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func insertNewline(_ sender: Any?) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholderString.draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
