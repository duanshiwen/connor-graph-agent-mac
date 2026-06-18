import SwiftUI
import ConnorGraphCore

private enum RSSSourcePreset: String, CaseIterable, Identifiable {
    case appleDeveloper
    case swiftBlog
    case hackerNews
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleDeveloper: "Apple Developer"
        case .swiftBlog: "Swift.org Blog"
        case .hackerNews: "Hacker News"
        case .custom: "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .appleDeveloper: "官方平台动态"
        case .swiftBlog: "Swift 语言与工具链更新"
        case .hackerNews: "技术社区热点"
        case .custom: "添加任意 RSS / Atom / JSON Feed"
        }
    }

    var feedURLString: String {
        switch self {
        case .appleDeveloper: "https://developer.apple.com/news/rss/news.rss"
        case .swiftBlog: "https://www.swift.org/blog/feed.xml"
        case .hackerNews: "https://hnrss.org/frontpage"
        case .custom: ""
        }
    }

    var guidance: String {
        switch self {
        case .appleDeveloper:
            "适合跟踪 Apple 平台、SDK、审核与生态变化。Connor 仅保存订阅源、抓取游标和本地阅读状态。"
        case .swiftBlog:
            "适合跟踪 Swift 语言、并发、Package Manager 和工具链公告。正文读取仍需显式工具调用。"
        case .hackerNews:
            "适合发现技术趋势。进入 Graph Memory 前必须先生成 evidence candidate 并人工审查。"
        case .custom:
            "输入自定义 feed URL。同步、状态变更、OPML 导入导出都经过 Connor Policy Engine 和 audit trail。"
        }
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
