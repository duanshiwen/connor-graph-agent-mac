import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentChatView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            AgentChatSessionListView(viewModel: viewModel)
                .frame(width: 304)
                .background(.ultraThinMaterial)

            Divider()

            Group {
                if viewModel.isBrowserVisible {
                    BrowserWorkspaceView(viewModel: viewModel)
                } else {
                    AgentChatConversationView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            AgentChatInspectorView(viewModel: viewModel)
                .frame(width: 320)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        }
        .navigationTitle("Connor Sessions")
        .onAppear { viewModel.reloadChatSessions() }
    }
}

private struct AgentChatSessionListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { viewModel.newChatSession() }) {
                Label("新建对话", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
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
                LazyVStack(alignment: .leading, spacing: 6) {
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
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct AgentChatSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: row.isFlagged ? "flag.fill" : (isSelected ? "message.fill" : "message"))
                        .font(.caption)
                        .foregroundStyle(row.isFlagged ? .orange : (isSelected ? .accentColor : .secondary))
                        .frame(width: 16)
                    Text(row.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentChatConversationView: View {
    @ObservedObject var viewModel: AppViewModel

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
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            if !viewModel.agentEventTimeline.isEmpty {
                AgentEventTimelineView(events: viewModel.agentEventTimeline)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
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
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .onChange(of: viewModel.transcript.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isSubmittingChat) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            AgentChatComposerView(viewModel: viewModel)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.20))
    }
}

private struct AgentChatConversationHeader: View {
    @ObservedObject var viewModel: AppViewModel

    private var selectedTitle: String {
        viewModel.chatSessions.first(where: { $0.id == viewModel.selectedChatSessionID })?.title ?? "智能体聊天"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 6) {
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
                    .padding(.top, 6)
                } label: {
                    Label("会话摘要", systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                }
                .padding(10)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct AgentEventTimelineView: View {
    var events: [AgentEventPresentation]

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
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
                        .padding(10)
                        .frame(width: 250, alignment: .leading)
                        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
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
            .padding(12)
            .frame(maxWidth: isUser ? 560 : 760, alignment: .leading)
            .background(messageBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isUser ? Color.clear : Color.secondary.opacity(0.12), lineWidth: 1)
            )

            if !isUser { Spacer(minLength: 80) }
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
            Spacer(minLength: 120)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
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

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(process.summary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if process.state == .running {
                    ThinkingDotsView()
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("完整对话历史（截至本轮回复前 \(process.fullConversationMessageCount) 条）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(process.conversationHistory) { historyRow in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
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
                            VStack(alignment: .leading, spacing: 8) {
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
            .padding(10)
            .frame(maxWidth: 700, alignment: .leading)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )

            Spacer(minLength: 120)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AgentChatPendingAssistantRow: View {
    var pending: AgentChatPendingAssistantPresentation

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 8) {
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
            .padding(12)
            .frame(maxWidth: 760, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )

            Spacer(minLength: 80)
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
        VStack(alignment: .leading, spacing: 8) {
            if let summary = row.turnMetadataSummary {
                HStack(spacing: 8) {
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
                VStack(alignment: .leading, spacing: 10) {
                    if let request = row.currentRequest {
                        MetadataBlock(title: "当前请求", text: request)
                    }

                    if !row.citationIDs.isEmpty {
                        MetadataChips(title: "引用", values: row.citationIDs)
                    }

                    if !row.expandedContextItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
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

private struct AgentChatComposerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("询问图谱智能体", text: $viewModel.chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                    )
                    .onSubmit { Task { await viewModel.submitChat() } }

                Button(action: { viewModel.isBrowserVisible = true }) {
                    Image(systemName: "safari")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .help("打开内嵌浏览器")

                Button(action: { Task { await viewModel.submitChat() } }) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingChat)
            }

            HStack(spacing: 8) {
                Label(viewModel.isSubmittingChat ? "处理中" : "图谱上下文", systemImage: viewModel.isSubmittingChat ? "clock.arrow.circlepath" : "link")
                if let inspection = viewModel.lastPromptInspection {
                    Text("约 \(inspection.estimatedPromptTokenCount) tokens")
                    Text(AgentChatMessagePresentation.budgetStatusText(inspection.promptBudgetStatus))
                        .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
                }
                Spacer()
                Text("按 Return 发送")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                FilterButton(title: "Inbox", isSelected: viewModel.sessionListFilter == .inbox) { viewModel.setSessionListFilter(.inbox) }
                FilterButton(title: "All", isSelected: viewModel.sessionListFilter == .all) { viewModel.setSessionListFilter(.all) }
                FilterButton(title: "Archive", isSelected: viewModel.sessionListFilter == .archived) { viewModel.setSessionListFilter(.archived) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
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
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session Inspector")
                        .font(.headline)
                    Text("Craft-style governance layer · Swift native")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let session = selectedSession {
                    sessionGovernance(session)
                    labels(session)
                    artifacts
                    graphMemory
                } else {
                    ContentUnavailableView("未选择会话", systemImage: "bubble.left.and.bubble.right", description: Text("从 Inbox 选择一个 session 查看治理信息。"))
                        .frame(minHeight: 260)
                }
            }
            .padding(16)
        }
    }

    private func sessionGovernance(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Governance")
                .font(.subheadline.weight(.semibold))
            Picker("Status", selection: Binding(
                get: { session.governance.status },
                set: { viewModel.setSelectedSessionStatus($0) }
            )) {
                ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button(session.governance.isFlagged ? "Unflag" : "Flag") { viewModel.toggleSelectedSessionFlag() }
                if session.governance.isArchived {
                    Button("Restore") { viewModel.restoreSelectedSession() }
                } else {
                    Button("Archive") { viewModel.archiveSelectedSession() }
                }
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 4) {
                Text("Messages: \(session.messages.count)")
                Text("Updated: \(session.updatedAt.formatted())")
                Text("Session ID: \(session.id)")
                    .textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labels(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Labels")
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var artifacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Artifacts")
                .font(.subheadline.weight(.semibold))
            if let dirs = viewModel.selectedSessionArtifactDirectories {
                ArtifactPathRow(label: "plans", path: dirs.plans.path)
                ArtifactPathRow(label: "data", path: dirs.data.path)
                ArtifactPathRow(label: "attachments", path: dirs.attachments.path)
                ArtifactPathRow(label: "exports", path: dirs.exports.path)
            } else {
                Text("Artifact directories are not available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var graphMemory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Graph Memory")
                .font(.subheadline.weight(.semibold))
            Text("Memory staging, extraction, admission and graph governance stay owned by Connor, not by the model SDK.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Label("Trace", systemImage: "point.3.connected.trianglepath.dotted")
                Spacer()
                Text("\(viewModel.graphExtractionTraces.count)")
            }
            HStack {
                Label("Hold Queue", systemImage: "tray.full")
                Spacer()
                Text("\(viewModel.admissionHoldQueueItems.count)")
            }
            HStack {
                Label("Memory Log", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(viewModel.memoryChangeLogEntries.count)")
            }
            .font(.caption)
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
