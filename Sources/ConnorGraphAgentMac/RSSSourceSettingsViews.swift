import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct RSSSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeRSSBrowserPresentation { viewModel.rssBrowserPresentation }
    private var selectedSource: RSSSource? { presentation.source(id: viewModel.selectedRSSSourceID) }
    private var selectedItem: RSSItemSummary? { presentation.item(id: viewModel.selectedRSSItemID) }

    var body: some View {
        Group {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 0) {
                    RSSBrowserTopBar(onAdd: { viewModel.isPresentingAddRSSSourceSheet = true })
                    Divider().opacity(0.6)
                    RSSItemDetailPane(source: selectedSource ?? presentation.source(id: selectedItem.sourceID), item: selectedItem)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
        .sheet(isPresented: $viewModel.isPresentingAddRSSSourceSheet) {
            AddRSSSourceSheet()
        }
    }
}

private struct RSSBrowserTopBar: View {
    var onAdd: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceM) {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text("RSS 阅读")
                    .font(.system(size: 24, weight: .semibold))
                Text("订阅源、抓取游标、阅读状态和 Graph evidence 候选由 Connor 本地治理。")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AppShellLayout.spaceM)
            Button(action: onAdd) { Label("添加订阅源", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, AppShellLayout.spaceXL)
        .padding(.vertical, AppShellLayout.spaceL)
    }
}

private struct RSSItemDetailPane: View {
    var source: RSSSource?
    var item: RSSItemSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                RSSItemHero(source: source, item: item)
                RSSInfoSection(title: "文章摘要", systemImage: "doc.text.magnifyingglass") {
                    Text(item.snippet.isEmpty ? "暂无摘要。" : item.snippet)
                        .font(AgentChatTypography.meta)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RSSInfoSection(title: "来源信息", systemImage: "dot.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                        RSSMetadataLine(label: "来源", value: source?.displayName ?? item.sourceID.rawValue)
                        RSSMetadataLine(label: "作者", value: item.author ?? "未知")
                        RSSMetadataLine(label: "链接", value: item.link?.absoluteString ?? "无")
                    }
                }
                RSSInfoSection(title: "治理提示", systemImage: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                        RSSChecklistRow(title: "列表读取不注入全文", isReady: true, detail: "AI 默认只读取 summary/snippet，需要正文时显式调用 content 工具。")
                        RSSChecklistRow(title: "阅读状态显式变更", isReady: true, detail: "已读、收藏、隐藏均通过 Policy Engine 审计。")
                        RSSChecklistRow(title: "记忆写入需 evidence", isReady: true, detail: "RSS 文章只能生成候选证据，不直接写入 Graph Memory。")
                    }
                }
            }
            .padding(AppShellLayout.spaceXL)
            .frame(maxWidth: AppShellLayout.contentMaxWidth, alignment: .leading)
        }
    }
}

private struct RSSItemHero: View {
    var source: RSSSource?
    var item: RSSItemSummary

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceL) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                Image(systemName: item.state.isRead ? "newspaper" : "newspaper.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AppShellLayout.spaceS) {
                    Text(item.title)
                        .font(AgentChatTypography.title)
                        .lineLimit(3)
                    RSSStatusPill(status: item.state.isRead ? "已读" : "未读", color: item.state.isRead ? .secondary : .blue)
                    if item.state.isStarred { RSSStatusPill(status: "收藏", color: .yellow, systemImage: "star.fill") }
                }
                Text(source?.displayName ?? item.sourceID.rawValue)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                HStack(spacing: AppShellLayout.spaceS) {
                    RSSStatusPill(status: item.publishedAt.formatted(date: .abbreviated, time: .shortened), color: .secondary, systemImage: "clock")
                    RSSStatusPill(status: item.author ?? "未知作者", color: .secondary, systemImage: "person")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppShellLayout.spaceL)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }
}

private struct RSSInfoSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
            Label(title, systemImage: systemImage).font(AgentChatTypography.callout)
            content
        }
        .padding(AppShellLayout.spaceL)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }
}

private struct RSSMetadataLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.meta)
                .textSelection(.enabled)
        }
    }
}

private struct RSSStatusPill: View {
    var status: String
    var color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(status)
        }
        .font(AgentChatTypography.microEmphasis)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct RSSChecklistRow: View {
    var title: String
    var isReady: Bool
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AgentChatTypography.metaEmphasis)
                Text(detail).font(AgentChatTypography.micro).foregroundStyle(.secondary)
            }
        }
    }
}
