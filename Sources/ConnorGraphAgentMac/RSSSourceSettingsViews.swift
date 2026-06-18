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

struct AddRSSSourceSheet: View {
    private enum Layout { static let sheetWidth: CGFloat = 640; static let iconSize: CGFloat = 44; static let labelWidth: CGFloat = 108 }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: RSSSourcePreset = .appleDeveloper
    @State private var feedURLString: String = RSSSourcePreset.appleDeveloper.feedURLString
    @State private var displayName: String = ""
    @State private var intervalMinutes: Int = 30
    @State private var openTarget: RSSSourceOpenTarget = .localReader

    private var saveDisabled: Bool { URL(string: feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            header
            RSSSetupSection(title: "订阅源") {
                RSSSetupRow("预设", labelWidth: Layout.labelWidth) {
                    Picker("预设", selection: $selectedPreset) {
                        ForEach(RSSSourcePreset.allCases) { preset in Text(preset.title).tag(preset) }
                    }
                    .onChange(of: selectedPreset) { _, newValue in
                        if !newValue.feedURLString.isEmpty { feedURLString = newValue.feedURLString }
                    }
                }
                RSSSetupRow("Feed URL", labelWidth: Layout.labelWidth) { TextField("https://example.com/feed.xml", text: $feedURLString).textFieldStyle(.roundedBorder) }
                RSSSetupRow("显示名称", labelWidth: Layout.labelWidth) { TextField("可选", text: $displayName).textFieldStyle(.roundedBorder) }
                RSSSetupRow("抓取间隔", labelWidth: Layout.labelWidth) { Picker("抓取间隔", selection: $intervalMinutes) { Text("15 分钟").tag(15); Text("30 分钟").tag(30); Text("1 小时").tag(60); Text("6 小时").tag(360) }.frame(width: 180) }
                RSSSetupRow("打开方式", labelWidth: Layout.labelWidth) { Picker("打开方式", selection: $openTarget) { Text("Connor 阅读器").tag(RSSSourceOpenTarget.localReader); Text("原网页").tag(RSSSourceOpenTarget.webpage); Text("外部浏览器").tag(RSSSourceOpenTarget.externalBrowser); Text("全文内容").tag(RSSSourceOpenTarget.fullContent) }.frame(width: 220) }
            }
            RSSHintCard(title: selectedPreset.subtitle, guidance: selectedPreset.guidance)
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存草稿") { dismiss() }.buttonStyle(.borderedProminent).disabled(saveDisabled) }
        }
        .padding(SettingsListLayout.spaceXL)
        .frame(width: Layout.sheetWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            ZStack { RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous).fill(Color.orange.opacity(0.13)); Image(systemName: "dot.radiowaves.left.and.right").font(SettingsListTypography.largeIcon).foregroundStyle(.orange) }
                .frame(width: Layout.iconSize, height: Layout.iconSize)
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("添加 RSS 订阅源").font(SettingsListTypography.header)
                Text("支持 RSS 2.0、Atom 与 JSON Feed。真实保存与同步继续由 Native RSS Runtime / Policy Engine 接入。")
                    .font(SettingsListTypography.rowSubtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
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

private struct RSSSetupSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            content
        }
        .padding(SettingsListLayout.spaceL)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
    }
}

private struct RSSSetupRow<Content: View>: View {
    var label: String
    var labelWidth: CGFloat
    @ViewBuilder var content: Content

    init(_ label: String, labelWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: SettingsListLayout.spaceM) {
            Text(label)
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            content
        }
    }
}

private struct RSSHintCard: View {
    var title: String
    var guidance: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Text(guidance)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsListLayout.spaceL)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
    }
}
