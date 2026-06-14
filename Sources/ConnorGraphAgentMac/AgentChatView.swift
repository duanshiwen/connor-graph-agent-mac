import SwiftUI
import AppKit
import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

enum ConnorCraftPalette {
    // Mirrors Craft Agents OSS renderer tokens:
    // --background: light oklch(0.98 0.003 265), dark oklch(0.2 0.005 270)
    // --foreground: light oklch(0.185 0.01 270), dark oklch(0.92 0.005 270)
    // --accent: light oklch(0.62 0.13 293), dark oklch(0.65 0.20 293)
    static let background = dynamicColor(light: "#F7F8FA", dark: "#151618")
    static let foreground = dynamicColor(light: "#111317", dark: "#E3E4E8")
    static let accent = dynamicColor(light: "#8A75CD", dark: "#9770FC")
    static let userBubble = foreground.opacity(0.05)
    static let userBubbleDimmed = foreground.opacity(0.03)
    static let sendButton = foreground
    static let sendButtonForeground = background
    static let stopButton = foreground.opacity(0.05)
    static let accentSoftFill = accent.opacity(0.14)
    static let accentSubtleFill = accent.opacity(0.08)
    static let accentBorder = accent.opacity(0.28)

    private static func dynamicColor(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return nsColor(hex: dark)
            }
            return nsColor(hex: light)
        })
    }

    private static func nsColor(hex: String) -> NSColor {
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else {
            return .controlAccentColor
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

enum AgentChatTypography {
    // Keep a small, semantic scale instead of one-off sizes. Apple HIG recommends
    // using font size, weight, and color to preserve legibility and hierarchy.
    static let largeIconSize: CGFloat = 48
    static let controlIconSize: CGFloat = 15
    static let smallIconSize: CGFloat = 13
    static let chevronIconSize: CGFloat = 13
    static let sendIconSize: CGFloat = 15

    static let title: Font = .system(size: 15.5, weight: .semibold)
    static let sectionTitle: Font = .headline.weight(.semibold)
    static let sessionTitle: Font = .system(size: 15, weight: .regular)
    static let sessionTitleEmphasis: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 15)
    static let bodyEmphasis: Font = .system(size: 15, weight: .semibold)
    static let callout: Font = .system(size: 14)
    static let calloutEmphasis: Font = .system(size: 14, weight: .semibold)
    static let meta: Font = .system(size: 13)
    static let metaEmphasis: Font = .system(size: 13, weight: .semibold)
    static let micro: Font = .system(size: 12)
    static let microEmphasis: Font = .system(size: 12, weight: .semibold)
    static let monoMeta: Font = .system(size: 13, design: .monospaced)
    static let monoMetaEmphasis: Font = .system(size: 13, weight: .semibold, design: .monospaced)
    static let monoMicro: Font = .system(size: 12, design: .monospaced)

    static var composerNSFont: NSFont { .systemFont(ofSize: 16) }
}

enum AgentChatLayout {
    static let spaceXS: CGFloat = 3
    static let spaceS: CGFloat = 6
    static let spaceM: CGFloat = 10
    static let spaceL: CGFloat = 14
    static let spaceXL: CGFloat = 20

    static let radiusS: CGFloat = 7
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 14
    static let radiusXL: CGFloat = 18

    static let hairlineOpacity: Double = 0.14
    static let chipHeight: CGFloat = 30
    static let iconButtonSize: CGFloat = 32
    static let primaryButtonSize: CGFloat = 34
    static let hitTargetSize: CGFloat = 44
    static let activityRowMinHeight: CGFloat = 24
    static let composerTextMinHeight: CGFloat = 56
    static let composerTextMaxHeight: CGFloat = 120
    static let composerInfoButtonWidth: CGFloat = 78
    static let modelMenuMaxWidth: CGFloat = 176

    static let chatContentMaxWidth: CGFloat = 720
    static let messageMaxWidth: CGFloat = chatContentMaxWidth
    static let userMessageMaxWidth: CGFloat = chatContentMaxWidth * 0.72
    static let assistantMessageMaxHeight: CGFloat = 600
    static let assistantMessageScrollbarGutter: CGFloat = 28
    static let processMaxWidth: CGFloat = chatContentMaxWidth
    static let messageSideInset: CGFloat = 0
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
        .environment(\.openURL, OpenURLAction { url in
            viewModel.openURLInCurrentChatBrowser(url)
            return .handled
        })
        .navigationTitle("康纳同学会话")
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
                SidebarActionButtonLabel(title: "新建对话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack {
                    Text("Inbox")
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
                    FlowLikeChips(values: row.labels.prefix(3).map(\.displayText))
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
    @State private var lastObservedSessionID: String?
    @State private var lastObservedTranscriptCount: Int = 0
    @State private var pendingSessionTranscriptReloadID: String?

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
                        if timelineSnapshot.isEmpty {
                            AgentChatEmptyStateView()
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ForEach(timelineSnapshot) { item in
                                if let message = item.message {
                                    AgentChatMessageRow(row: message)
                                        .id(item.id)
                                } else if let process = item.process {
                                    AgentChatTurnProcessRow(
                                        process: process,
                                        events: activityEvents(for: process, latestProcessID: latestProcessID),
                                        onOpenDetail: { event in
                                            activityDetailEvent = event
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
            if let event = activityDetailEvent {
                AgentActivityDetailOverlay(event: event) {
                    activityDetailEvent = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .padding(.horizontal, AgentChatLayout.spaceL)
        .padding(.vertical, AgentChatLayout.spaceM)
    }
}

private struct AgentChatConversationHeader: View {
    @ObservedObject var viewModel: AppViewModel

    private var selectedTitle: String {
        viewModel.chatSessions.first(where: { $0.id == viewModel.selectedChatSessionID })?.title ?? "智能体聊天"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Text(selectedTitle)
                .font(AgentChatTypography.sectionTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

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

    private var selectedSession: AgentSession? {
        viewModel.chatSessions.first { $0.id == viewModel.selectedChatSessionID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    Text("信息")
                        .font(AgentChatTypography.sectionTitle)
                    Text("会话设置、标签和文件")
                        .font(AgentChatTypography.meta)
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
                if session.governance.isArchived {
                    Button("恢复") { viewModel.restoreSelectedSession() }
                } else {
                    Button("归档") { viewModel.archiveSelectedSession() }
                }
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
            ForEach(viewModel.governanceConfig.labels.filter { $0.valueType == .boolean }) { definition in
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
        .padding(AgentChatLayout.spaceM)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
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

