import SwiftUI
import ConnorGraphBase
import ConnorGraphAppSupport

// MARK: - 小程序列表（左列）

/// 「小程序」列表：本机 + 云端汇总、分页加载、可搜索。
struct MiniAppListPane: View {
    @Bindable var model: MiniAppFeatureModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
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
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { model.loadIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("小程序")
                    .font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新小程序列表")
            .disabled(model.isLoading)
        }
        .padding(12)
    }

    private var summaryText: String {
        if model.entries.isEmpty { return "本机 + 云端汇总" }
        let total = model.localCount + model.cloudTotal
        return "共 \(total) 个 · 本机 \(model.localCount) · 云端 \(model.cloudTotal)"
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索名称 / 功能 / 领域…", text: $model.searchText)
                .textFieldStyle(.plain)
                .onChange(of: model.searchText) { _, _ in
                    model.searchTextDidChange()
                }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    model.searchTextDidChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var list: some View {
        List(selection: $model.selectedAppID) {
            ForEach(model.entries) { entry in
                MiniAppRowView(entry: entry)
                    .tag(entry.appID)
            }
        }
        .listStyle(.sidebar)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("还没有小程序")
                .font(.headline)
            Text("在对话里让康纳用 base.app.create 创建一个，\n或稍后刷新查看云端共享的小程序。")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                MiniAppBadge(text: entry.sourceBadge, color: entry.source == .local ? .teal : .indigo)
                MiniAppBadge(text: entry.scopeBadge, color: entry.scope == .privateOnly ? .gray : .blue)
                MiniAppBadge(text: entry.relationBadge, color: entry.isOwned ? .green : .purple)
                Spacer()
            }
            if !entry.purpose.isEmpty {
                Text(entry.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if !entry.domain.isEmpty {
                    Label(entry.domain, systemImage: "scope")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.methodCount) 个方法 · \(entry.tableCount) 张表")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.ownerName.isEmpty {
                    Text("by \(entry.ownerName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 小程序详情（右列）

/// 「小程序」详情：功能说明 + 汇总提示。
struct MiniAppDetailPane: View {
    @Bindable var model: MiniAppFeatureModel

    var body: some View {
        Group {
            if let detail = model.selectedDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overviewSection(detail)
                        functionSection(detail)
                        summarySection(detail)
                        guideSection(detail)
                    }
                    .padding(20)
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
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func overviewSection(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(detail.name)
                    .font(.title2.weight(.semibold))
                MiniAppBadge(text: detail.sourceBadge, color: detail.source == .local ? .teal : .indigo)
                MiniAppBadge(text: detail.scopeBadge, color: detail.scope == .privateOnly ? .gray : .blue)
                MiniAppBadge(text: detail.relationBadge, color: detail.isOwned ? .green : .purple)
            }
            if !detail.ownerName.isEmpty {
                Label("创建者：\(detail.ownerName)", systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label("更新于 \(detail.updatedAt.isEmpty ? "—" : detail.updatedAt)", systemImage: "clock")
                Label("风险等级：\(detail.riskLevel)", systemImage: "shield.lefthalf.filled")
                Label("SDK v\(detail.sdkVersion)", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func functionSection(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("功能说明", systemImage: "text.alignleft")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                if !detail.domain.isEmpty {
                    Text("领域：\(detail.domain)")
                        .font(.callout)
                }
                Text(detail.purpose.isEmpty ? "（暂无功能说明）" : detail.purpose)
                    .font(.callout)
                    .foregroundStyle(detail.purpose.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func summarySection(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("汇总提示", systemImage: "list.bullet.rectangle")
                .font(.headline)
            HStack(spacing: 12) {
                MiniAppStatCard(value: "\(detail.methodCount)", title: "方法")
                MiniAppStatCard(value: "\(detail.tableCount)", title: "数据表")
                MiniAppStatCard(value: "\(detail.dataTableCount)", title: "已有数据表")
                MiniAppStatCard(value: "\(detail.capabilities.count)", title: "能力")
            }
            if !detail.methods.isEmpty {
                Text("方法：\(detail.methods.joined(separator: "、"))")
                    .font(.callout)
                    .textSelection(.enabled)
            }
            if !detail.tableNames.isEmpty {
                Text("数据表：\(detail.tableNames.joined(separator: "、"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func guideSection(_ detail: MiniAppDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使用提示", systemImage: "lightbulb")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.guideSummary)
                    .font(.callout)
                    .textSelection(.enabled)
                ForEach(detail.guideNotes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .padding(.top, 5)
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
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
        .frame(minWidth: 64)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
