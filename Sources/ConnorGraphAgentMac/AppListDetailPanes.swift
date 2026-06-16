import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct CraftListPaneView: View {
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

struct CraftSessionListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text(sessionListTitle)
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if filteredSessions.isEmpty {
                if viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("暂无会话", systemImage: "bubble.left", description: Text("点击左上角新建会话开始。"))
                        .padding(.top, 80)
                } else {
                    ContentUnavailableView("没有匹配的会话", systemImage: "magnifyingglass", description: Text("搜索会匹配会话标题和消息内容。"))
                        .padding(.top, 80)
                }
            } else {
                List(filteredSessions) { session in
                    CraftSessionRow(
                        row: AgentChatSessionPresentation(session: session),
                        isSelected: session.id == viewModel.selectedChatSessionID,
                        isRunning: viewModel.isChatSessionSubmitting(session.id),
                        isRegeneratingTitle: viewModel.regeneratingTitleSessionIDs.contains(session.id),
                        hasRunningBackgroundTask: !viewModel.canDeleteChatSession(session.id),
                        labelDefinitions: viewModel.governanceConfig.labels,
                        onSelect: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                viewModel.selectChatSession(session.id)
                            }
                        },
                        onRename: { title in viewModel.renameChatSession(session.id, title: title) },
                        onSetStatus: { status in viewModel.setChatSessionStatus(session.id, status: status) },
                        onToggleLabel: { labelID in viewModel.toggleChatSessionLabel(session.id, labelID: labelID) },
                        onRegenerateTitle: { viewModel.regenerateChatSessionTitle(session.id) },
                        onDelete: { viewModel.deleteChatSession(session.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { viewModel.reloadChatSessions() }
    }

    private var filteredSessions: [AgentSession] {
        AgentSessionTextSearchFilter().filter(viewModel.chatSessions, query: viewModel.sessionSearchQuery)
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

struct CraftDetailPaneView: View {
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


struct CraftSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var isRunning: Bool
    var isRegeneratingTitle: Bool
    var hasRunningBackgroundTask: Bool
    var labelDefinitions: [AgentSessionLabelDefinition]
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onSetStatus: (AgentSessionStatus) -> Void
    var onToggleLabel: (String) -> Void
    var onRegenerateTitle: () -> Void
    var onDelete: () -> Void

    @State private var isEditingTitle: Bool = false
    @State private var titleDraft: String = ""
    @State private var isDeleteConfirmationPresented: Bool = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onRegenerateTitle()
                } label: {
                    Label("重设标题", systemImage: "sparkles")
                }
                .disabled(isRegeneratingTitle)
                .tint(.orange)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(hasRunningBackgroundTask)
            }
            .contextMenu { contextMenuItems }
            .onChange(of: row.title) { _, newTitle in
            guard !isEditingTitle else { return }
            titleDraft = newTitle
        }
            .onAppear { titleDraft = row.title }
            .confirmationDialog("删除这个会话？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
                .disabled(hasRunningBackgroundTask)
            Button("取消", role: .cancel) {}
            } message: {
                Text(hasRunningBackgroundTask ? "此会话仍有后台任务正在运行,请等待任务结束后再删除。" : "删除后会话将从列表中移除。")
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Menu {
            ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    Label(status.displayName, systemImage: status == row.status ? "checkmark.circle.fill" : icon(for: status))
                }
            }
        } label: {
            Label("更改状态", systemImage: "circle.dashed")
        }

        Menu {
            if labelDefinitions.isEmpty {
                Button {} label: {
                    Label("暂无可切换标签", systemImage: "tag.slash")
                }
                .disabled(true)
            } else {
                ForEach(labelDefinitions) { definition in
                    Button {
                        onToggleLabel(definition.id)
                    } label: {
                        Label(definition.name, systemImage: row.labels.contains(where: { $0.id == definition.id }) ? "checkmark.circle.fill" : "tag")
                    }
                }
            }
        } label: {
            Label("标签", systemImage: "tag")
        }

        Divider()

        Button {
            beginTitleEdit()
        } label: {
            Label("重命名", systemImage: "pencil")
        }

        Button {
            onRegenerateTitle()
        } label: {
            Label("重设标题", systemImage: "sparkles")
        }
        .disabled(isRegeneratingTitle)

        Divider()

        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("删除", systemImage: "trash")
        }
        .disabled(hasRunningBackgroundTask)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if isRunning || isRegeneratingTitle {
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
                    if isEditingTitle {
                        TextField("会话标题", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .focused($isTitleFocused)
                            .lineLimit(1)
                            .onSubmit { commitTitleEdit() }
                    } else {
                        Text(row.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                            .onTapGesture(count: 2) { beginTitleEdit() }
                    }
                    Spacer(minLength: 4)
                    if isRunning {
                        Text("运行中")
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(Color.accentColor)
                    } else if isRegeneratingTitle {
                        Text("生成中")
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
                    Text("\(row.messageCount) 条消息")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                if !row.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(row.labels.prefix(3)), id: \.id) { label in
                            Text(label.id)
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
        .background(rowBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if !isEditingTitle { onSelect() }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitleEdit() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var rowBackgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor)
    }


    private func beginTitleEdit() {
        titleDraft = row.title
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard !trimmed.isEmpty, trimmed != row.title else {
            titleDraft = row.title
            return
        }
        onRename(trimmed)
    }


    private func icon(for status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle.fill"
        case .blocked: "nosign"
        case .cancelled: "xmark.circle"
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
        case .cancelled: .gray
        case .archived: .gray
        }
    }
}


struct CraftSettingsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
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

struct SettingsCategoryRow: View {
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CraftSimpleListPane: View {
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

