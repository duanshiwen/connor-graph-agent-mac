import SwiftUI
import ConnorGraphBase
import ConnorGraphAppSupport

// MARK: - 小程序列表（左列）

/// 「小程序」列表：本机 + 云端汇总、分页加载；筛选关键词由统一搜索注入。
struct MiniAppListPane: View {
    @Bindable var model: MiniAppFeatureModel

    var body: some View {
        VStack(spacing: 0) {
            AppListPaneHeader(title: "小程序") {
                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.appIcon)
                .disabled(model.isLoading)
                .help("刷新小程序列表")
                .accessibilityLabel("刷新小程序列表")
            }

            ListSearchFilterBanner(query: model.searchText, sourceTitle: "小程序") {
                model.clearSearch()
            }

            if model.isLoading && model.entries.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载小程序…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                emptyState
            } else {
                list
                if model.cloudHasMore || model.isLoadingMore {
                    Divider()
                    paginationFooter
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.loadIfNeeded() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: AppListCardLayout.spacing) {
                ForEach(model.entries) { entry in
                    MiniAppRowView(
                        entry: entry,
                        isSelected: entry.appID == model.selectedAppID,
                        onSelect: { model.select(appID: entry.appID) }
                    )
                }
            }
            .padding(.horizontal, AppListCardLayout.horizontalInset)
            .padding(.top, AppShellLayout.spaceS)
            .padding(.bottom, AppShellLayout.spaceM)
        }
        .scrollContentBackground(.hidden)
    }

    private var paginationFooter: some View {
        HStack(spacing: 8) {
            Text("云端第 \(model.cloudPage) 页 / 共 \(model.cloudTotal) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.loadMore()
            } label: {
                if model.isLoadingMore {
                    ProgressView().controlSize(.small)
                } else {
                    Text("加载更多")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isLoadingMore)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var isFiltering: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(isFiltering ? "没有找到相关的小程序" : "这里还没有小程序")
                .font(.headline)
            Text(isFiltering ? "换个关键词试试，或清除搜索后查看全部小程序。" : "在对话里直接告诉康纳你想做什么，它可以帮你创建一个小程序；\n云端共享的小程序也会自动出现在这里。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.errorMessage != nil {
                Text(model.errorMessage!)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 小程序行

private struct MiniAppRowView: View {
    let entry: MiniAppEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppListCardLayout.contentPadding) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: AppListCardLayout.contentSpacing) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(AppListCardLayout.titleLineLimit)
                        MiniAppBadge(text: entry.sourceBadge, color: entry.source == .local ? .teal : .indigo)
                        MiniAppBadge(text: entry.scopeBadge, color: entry.scope == .privateOnly ? .gray : .blue)
                        MiniAppBadge(text: entry.relationBadge, color: entry.isOwned ? .green : .purple)
                        Spacer(minLength: 4)
                    }
                    if !entry.purpose.isEmpty {
                        Text(entry.purpose)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        if !entry.domain.isEmpty {
                            Label(entry.domain, systemImage: "scope")
                                .font(AppListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(entry.methodCount) 个方法 · \(entry.tableCount) 张表")
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if !entry.ownerName.isEmpty {
                            Text("by \(entry.ownerName)")
                                .font(AppListTypography.rowCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .appListRowSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 小程序详情（右列）

/// 「小程序」详情：Hero 卡片 + 分节卡片，宽度/样式/分割方式对齐 RSS、邮件详情页。
struct MiniAppDetailPane: View {
    @Bindable var model: MiniAppFeatureModel

    var body: some View {
        Group {
            if let detail = model.selectedDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                        MiniAppHeroCard(detail: detail)
                        MiniAppDetailSection(title: "功能说明", systemImage: "text.alignleft") {
                            functionContent(detail)
                        }
                        MiniAppDetailSection(title: "汇总提示", systemImage: "list.bullet.rectangle") {
                            summaryContent(detail)
                        }
                        MiniAppDetailSection(title: "使用提示", systemImage: "lightbulb") {
                            guideContent(detail)
                        }
                    }
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.vertical, AgentChatLayout.spaceL)
                    .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else if model.detailIsLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载详情…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text("选择一个小程序查看详情")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let error = model.detailErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppShellColors.detailBackground)
    }

    private func functionContent(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if !detail.domain.isEmpty {
                Text("领域：\(detail.domain)")
                    .font(AgentChatTypography.body)
                    .foregroundStyle(.secondary)
            }
            Text(detail.purpose.isEmpty ? "（暂无功能说明）" : detail.purpose)
                .font(AgentChatTypography.body)
                .foregroundStyle(detail.purpose.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryContent(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            HStack(spacing: AgentChatLayout.spaceS) {
                MiniAppStatCard(value: "\(detail.methodCount)", title: "方法")
                MiniAppStatCard(value: "\(detail.tableCount)", title: "数据表")
                MiniAppStatCard(value: "\(detail.dataTableCount)", title: "已有数据表")
                MiniAppStatCard(value: "\(detail.capabilities.count)", title: "能力")
            }
            if !detail.methods.isEmpty {
                Text("方法：\(detail.methods.joined(separator: "、"))")
                    .font(AgentChatTypography.meta)
                    .textSelection(.enabled)
            }
            if !detail.tableNames.isEmpty {
                Text("数据表：\(detail.tableNames.joined(separator: "、"))")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guideContent(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if !detail.guideSummary.isEmpty {
                Text(detail.guideSummary)
                    .font(AgentChatTypography.body)
                    .textSelection(.enabled)
            }
            ForEach(detail.guideNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .padding(.top, 5)
                    Text(note)
                        .font(AgentChatTypography.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 小程序详情卡片

private struct MiniAppHeroCard: View {
    var detail: MiniAppDetail

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
                    Text(detail.name)
                        .font(AgentChatTypography.title)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    MiniAppBadge(text: detail.sourceBadge, color: detail.source == .local ? .teal : .indigo)
                    MiniAppBadge(text: detail.scopeBadge, color: detail.scope == .privateOnly ? .gray : .blue)
                    MiniAppBadge(text: detail.relationBadge, color: detail.isOwned ? .green : .purple)
                }
                if !detail.ownerName.isEmpty {
                    Label("创建者：\(detail.ownerName)", systemImage: "person.crop.circle")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: AgentChatLayout.spaceS) {
                    MiniAppMetaPill(status: "更新于 \(detail.updatedAt.isEmpty ? "—" : detail.updatedAt)", color: .secondary, systemImage: "clock")
                    MiniAppMetaPill(status: "风险等级：\(detail.riskLevel)", color: .secondary, systemImage: "shield.lefthalf.filled")
                    MiniAppMetaPill(status: "SDK v\(detail.sdkVersion)", color: .secondary, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppShellLayout.spaceL)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }
}

private struct MiniAppDetailSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.primary)
            content
        }
        .padding(AppShellLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }
}

private struct MiniAppMetaPill: View {
    var status: String
    var color: Color
    var systemImage: String? = nil

    var body: some View {
        Label {
            Text(status)
                .lineLimit(1)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .font(AgentChatTypography.micro)
        .foregroundStyle(color)
        .padding(.horizontal, AgentChatLayout.spaceS)
        .frame(height: 23)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 组件

struct MiniAppBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

private struct MiniAppStatCard: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppShellColors.hairline, lineWidth: 1))
    }
}
