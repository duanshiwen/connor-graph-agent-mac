import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel
    @State private var sidebarSelection: SidebarItem? = .agentChat
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            CraftPrimarySidebarView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
                .background(.bar)
                .controlSize(.small)
        } content: {
            CraftListPaneView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 314, max: 380)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))
                .controlSize(.small)
        } detail: {
            CraftDetailPaneView(viewModel: viewModel, selection: sidebarSelection ?? .agentChat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(.small)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索会话标题和内容", text: $viewModel.sessionSearchQuery)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
                    if !viewModel.sessionSearchQuery.isEmpty {
                        Button(action: { viewModel.sessionSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.openProjectGitHubHelp() }) {
                    Label("帮助", systemImage: "questionmark.circle")
                }
                .help("用内置浏览器打开项目 GitHub 页面")
            }
        }
        .overlay(alignment: .topLeading) {
            BrowserBackgroundTaskRunnerView(viewModel: viewModel)
        }
        .frame(minWidth: 1120, minHeight: 680)
        .onAppear {
            sidebarSelection = viewModel.selection ?? .agentChat
            viewModel.reloadChatSessions()
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            viewModel.deferViewUpdate {
                viewModel.selection = newSelection
            }
        }
        .onChange(of: viewModel.selection) { _, newSelection in
            if sidebarSelection != newSelection {
                sidebarSelection = newSelection
            }
        }
        .sheet(isPresented: $viewModel.isCommandPalettePresented) {
            ConnorCommandPaletteView(viewModel: viewModel)
        }
    }

}

private enum AppListTypography {
    static let actionTitle: Font = .system(size: 13.5, weight: .regular)
    static let actionIcon: Font = .system(size: 14.5, weight: .medium)
    static let header: Font = .system(size: 15.5, weight: .semibold)
    static let rowTitle: Font = .system(size: 14.5, weight: .regular)
    static let rowTitleSelected: Font = .system(size: 14.5, weight: .semibold)
    static let rowSubtitle: Font = .system(size: 12.5)
    static let rowCaption: Font = .system(size: 12.5)
    static let rowCaptionEmphasized: Font = .system(size: 12.5, weight: .semibold)
}

struct SidebarActionButtonLabel: View {
    var title: String
    var systemImage: String
    var fillsWidth: Bool = true
    var titleFont: Font = AppListTypography.actionTitle
    var iconFont: Font = AppListTypography.actionIcon
    var minHeight: CGFloat = 24

    var body: some View {
        Label {
            Text(title)
                .font(titleFont)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(iconFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: 15, alignment: .center)
        }
        .foregroundStyle(Color.primary)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight, alignment: .leading)
        .padding(.horizontal, 7)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SidebarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: configuration.isPressed ? 0 : 0.5, x: 0, y: configuration.isPressed ? 0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(isPressed ? 0.78 : 0.96)
    }

    private func borderColor(isPressed: Bool) -> Color {
        Color(nsColor: .separatorColor)
            .opacity(isPressed ? 0.42 : 0.28)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        Color.black.opacity(isPressed ? 0.04 : 0.08)
    }
}

private struct CraftPrimarySidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?
    @State private var sessionsExpanded = true
    @State private var labelsExpanded = true
    @State private var sourcesExpanded = true
    @State private var automationExpanded = true

    var body: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.newChatSession()
                select(.agentChat)
            } label: {
                SidebarActionButtonLabel(title: "新建会话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SidebarDisclosure(title: "所有会话", systemImage: "tray", isExpanded: $sessionsExpanded) {
                        SidebarRow(title: "全部", systemImage: "bubble.left.and.bubble.right", count: allSessionsCount, isSelected: selection == .agentChat && viewModel.sessionListFilter == .all) {
                            viewModel.setSessionListFilter(.all)
                            select(.agentChat)
                        }
                        SidebarRow(title: "收件箱", systemImage: "tray.full", count: inboxCount, isSelected: selection == .agentChat && viewModel.sessionListFilter == .inbox) {
                            viewModel.setSessionListFilter(.inbox)
                            select(.agentChat)
                        }
                        ForEach(viewModel.governanceConfig.statuses.sorted { $0.sortOrder < $1.sortOrder }) { status in
                            if let sessionStatus = AgentSessionStatus(rawValue: status.id) {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: count(for: sessionStatus), isSelected: selection == .agentChat && viewModel.sessionListFilter == .status(sessionStatus)) {
                                    viewModel.setSessionListFilter(.status(sessionStatus))
                                    select(.agentChat)
                                }
                            }
                        }
                    }

                    SidebarDisclosure(title: "标签", systemImage: "tag", isExpanded: $labelsExpanded) {
                        if viewModel.governanceConfig.labels.isEmpty {
                            SidebarMutedText("暂无标签")
                        } else {
                            ForEach(viewModel.governanceConfig.labels) { label in
                                SidebarRow(title: label.name, systemImage: "tag", count: count(forLabel: label.id), isSelected: selection == .agentChat && viewModel.sessionListFilter == .label(label.id)) {
                                    viewModel.setSessionListFilter(.label(label.id))
                                    select(.agentChat)
                                }
                            }
                        }
                    }

                    SidebarRow(title: "数据源", systemImage: "externaldrive.connected.to.line.below", count: viewModel.sourceRuntimeConfigurations.count, isSelected: selection == .sources) { select(.sources) }

                    SidebarRow(title: "技能", systemImage: "bolt", count: viewModel.skillRuntimeDefinitions.count, isSelected: selection == .skills) { select(.skills) }

                    SidebarDisclosure(title: "自动化", systemImage: "wand.and.stars", isExpanded: $automationExpanded) {
                        SidebarRow(title: "定时任务", systemImage: "clock", count: viewModel.automationConfig.rules.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "事件触发", systemImage: "dot.radiowaves.left.and.right", count: viewModel.automationTriggerRecords.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "智能体", systemImage: "shippingbox", count: viewModel.productOSRegistry.skills.count, isSelected: selection == .productOS) { select(.productOS) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                SidebarRow(title: "设置", systemImage: "gearshape", count: nil, isSelected: selection == .llmSettings) { select(.llmSettings) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var countSourceSessions: [AgentSession] {
        viewModel.allChatSessions.isEmpty ? viewModel.chatSessions : viewModel.allChatSessions
    }

    private var allSessionsCount: Int {
        countSourceSessions.count
    }

    private var inboxCount: Int {
        countSourceSessions.filter { !$0.governance.isArchived }.count
    }

    private func count(for status: AgentSessionStatus) -> Int {
        countSourceSessions.filter { !$0.governance.isArchived && $0.governance.status == status }.count
    }

    private func count(forLabel labelID: String) -> Int {
        countSourceSessions.filter { session in
            !session.governance.isArchived && session.governance.labels.contains { $0.id == labelID }
        }.count
    }

    private func select(_ item: SidebarItem) {
        selection = item
        viewModel.selection = item
    }
}

private struct CraftListPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            switch selection ?? .agentChat {
            case .agentChat:
                CraftSessionListPane(viewModel: viewModel)
            case .llmSettings:
                CraftSettingsListPane(viewModel: viewModel, selection: $selection)
            case .sources:
                CraftSimpleListPane(title: "数据源", subtitle: "MCP Source Runtime", rows: viewModel.sourceRuntimeConfigurations.map(\.displayName))
            case .skills:
                CraftSimpleListPane(title: "技能", subtitle: "Skill Runtime", rows: viewModel.skillRuntimeDefinitions.map { $0.manifest.name })
            case .automation:
                CraftSimpleListPane(title: "自动化", subtitle: "事件触发与执行历史", rows: viewModel.automationConfig.rules.map(\.name))
            case .productOS:
                CraftSimpleListPane(title: "Product OS", subtitle: "本地控制面模块", rows: viewModel.productOSRegistry.sources.map(\.displayName) + viewModel.productOSRegistry.skills.map(\.displayName))
            default:
                CraftSimpleListPane(title: (selection ?? .agentChat).rawValue, subtitle: "康纳同学工作区", rows: [])
            }
        }
    }
}

private struct CraftSessionListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(sessionListTitle)
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()
                    Button(action: { viewModel.reloadChatSessions() }) {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.borderless)
                    .help("刷新/过滤")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSessions) { session in
                        CraftSessionRow(
                            row: AgentChatSessionPresentation(session: session),
                            isSelected: session.id == viewModel.selectedChatSessionID,
                            isRunning: session.id == viewModel.submittingChatSessionID
                        ) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                viewModel.selectChatSession(session.id)
                            }
                        }
                    }
                    if filteredSessions.isEmpty {
                        if viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView("暂无会话", systemImage: "bubble.left", description: Text("点击左上角新建会话开始。"))
                                .padding(.top, 80)
                        } else {
                            ContentUnavailableView("没有匹配的会话", systemImage: "magnifyingglass", description: Text("搜索会匹配会话标题和消息内容。"))
                                .padding(.top, 80)
                        }
                    }
                }
                .padding(8)
            }
        }
        .task { viewModel.reloadChatSessions() }
    }

    private var filteredSessions: [AgentSession] {
        AgentSessionTextSearchFilter().filter(viewModel.chatSessions, query: viewModel.sessionSearchQuery)
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .inbox: "所有会话"
        case .archived: "已归档"
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

private struct CraftDetailPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    var selection: SidebarItem

    var body: some View {
        Group {
            switch selection {
            case .entities:
                GraphEntitiesView(entities: viewModel.entities, statements: viewModel.statements, episodes: viewModel.episodes)
            case .search:
                SearchView(viewModel: viewModel)
            case .observeLog:
                ObserveLogView(entries: viewModel.observeLogEntries)
            case .agentChat:
                AgentChatView(viewModel: viewModel)
            case .promotionQueue:
                PromotionQueueView(viewModel: viewModel)
            case .graphWriteCandidates:
                GraphWriteCandidateReviewView(viewModel: viewModel)
            case .pendingApprovals:
                AgentPendingApprovalReviewView(viewModel: viewModel)
            case .memoryChangeLog:
                MemoryChangeLogView(viewModel: viewModel)
            case .extractionDiagnostics:
                GraphExtractionDiagnosticsView(viewModel: viewModel)
            case .automation:
                AutomationRuntimePanelView(viewModel: viewModel)
            case .productOS:
                ProductOSRegistryView(viewModel: viewModel)
            case .sources:
                SourceRuntimePanelView(viewModel: viewModel)
            case .skills:
                SkillRuntimePanelView(viewModel: viewModel)
            case .llmSettings:
                ConnorSettingsDetailView(viewModel: viewModel)
            }
        }
    }
}


private struct CraftSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var isRunning: Bool
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: row.isFlagged ? "pin.fill" : icon(for: row.status))
                    .foregroundStyle(row.isFlagged ? .orange : (isSelected ? .accentColor : .secondary))
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.title)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isRunning {
                        Text("运行中")
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(row.relativeUpdatedTime)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(row.statusText)
                        .font(AppListTypography.rowCaptionEmphasized)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(row.status).opacity(0.14), in: Capsule())
                    Text("\(row.messageCount) msgs")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                if !row.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(row.labels.prefix(3)), id: \.stableID) { label in
                            Text(label.displayText)
                                .font(AppListTypography.rowCaption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(SessionMouseDownHandler(action: action))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func icon(for status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle.fill"
        case .blocked: "nosign"
        case .archived: "archivebox"
        }
    }

    private func statusColor(_ status: AgentSessionStatus) -> Color {
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

private struct SessionMouseDownHandler: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> MouseDownView {
        let view = MouseDownView(frame: .zero)
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MouseDownView, context: Context) {
        nsView.action = action
    }

    final class MouseDownView: NSView {
        var action: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            action?()
        }
    }
}

private struct CraftSettingsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            Divider()
            VStack(spacing: 0) {
                ForEach(ConnorSettingsSection.allCases) { section in
                    SettingsCategoryRow(
                        title: section.title,
                        subtitle: section.subtitle,
                        systemImage: section.systemImage,
                        isSelected: viewModel.selectedSettingsSection == section
                    ) {
                        selection = .llmSettings
                        viewModel.selectSettingsSection(section)
                    }
                }
            }
            .padding(10)
            Spacer()
        }
    }
}

private struct SettingsCategoryRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppListTypography.rowTitleSelected)
                    Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CraftSimpleListPane: View {
    var title: String
    var subtitle: String
    var rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(title).font(AppListTypography.header)
                Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.isEmpty ? ["在右侧查看详情"] : rows, id: \.self) { row in
                        Text(row)
                            .font(AppListTypography.rowTitle)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct SidebarDisclosure<Content: View>: View {
    var title: String
    var systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(.leading, 12)
            .padding(.top, 3)
        } label: {
            Label(title, systemImage: systemImage)
                .font(AppListTypography.rowTitleSelected)
        }
        .disclosureGroupStyle(.automatic)
    }
}

private struct SidebarRow: View {
    var title: String
    var systemImage: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(AppListTypography.rowCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarMutedText: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(AppListTypography.rowSubtitle)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
