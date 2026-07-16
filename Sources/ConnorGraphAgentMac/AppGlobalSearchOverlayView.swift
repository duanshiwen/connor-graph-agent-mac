import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct AppGlobalSearchOverlayView: View {
    @Bindable var model: GlobalSearchFeatureModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var browserHistoryPage: Int = 0
    @State private var contentHeight: CGFloat = 0

    private enum Layout {
        static let width: CGFloat = 640
        static let maxHeight: CGFloat = 760
    }

    private let browserHistoryPageSize = 3
    private var state: GlobalSearchPreviewState { model.previewState }
    private var query: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var shouldScroll: Bool { contentHeight > Layout.maxHeight }

    var body: some View {
        Group {
            if shouldScroll {
                ScrollView(.vertical) {
                    overlayContent
                }
                .scrollIndicators(.visible)
                .frame(width: Layout.width, height: Layout.maxHeight, alignment: .topLeading)
            } else {
                overlayContent
                    .frame(width: Layout.width, alignment: .topLeading)
            }
        }
        .background(alignment: .topLeading) {
            measuredOverlayContent
        }
        .background(.regularMaterial, in: overlayShape)
        .overlay(glassEdgeHighlight)
        .overlay(glassEdgeLowlight)
        .shadow(
            color: .black.opacity(GlobalSearchOverlayGlassStyle.outerShadowOpacity),
            radius: GlobalSearchOverlayGlassStyle.outerShadowRadius,
            x: 0,
            y: GlobalSearchOverlayGlassStyle.outerShadowY
        )
        .onPreferenceChange(GlobalSearchOverlayContentHeightKey.self) { height in
            contentHeight = height
        }
        .onChange(of: state.query) { _, _ in
            browserHistoryPage = 0
        }
    }

    private var overlayShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
    }

    private var glassEdgeHighlight: some View {
        overlayShape
            .stroke(Color.white.opacity(edgeHighlightOpacity), lineWidth: 1)
            .blendMode(.overlay)
    }

    private var glassEdgeLowlight: some View {
        overlayShape
            .stroke(Color.black.opacity(edgeLowlightOpacity), lineWidth: 1)
            .blendMode(.softLight)
    }

    private var edgeHighlightOpacity: Double {
        colorScheme == .dark
            ? GlobalSearchOverlayGlassStyle.edgeHighlightOpacityDark
            : GlobalSearchOverlayGlassStyle.edgeHighlightOpacityLight
    }

    private var edgeLowlightOpacity: Double {
        colorScheme == .dark
            ? GlobalSearchOverlayGlassStyle.edgeLowlightOpacityDark
            : GlobalSearchOverlayGlassStyle.edgeLowlightOpacityLight
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            if query.isEmpty && state == .empty {
                recentSearchesSection
            } else {
                actionRows
                tokenChips

                chatSessionSection(results: state.chatSessionResults)
                knowledgeMarketplaceSection(results: state.knowledgeBaseResults)
                resultSection(kind: .calendar, results: state.calendarResults)
                resultSection(kind: .rss, results: state.rssResults)
                resultSection(kind: .mail, results: state.mailResults)
                browserHistorySection(results: state.browserHistoryResults)

                if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                    errorRow(errorMessage)
                }
            }
        }
        .padding(AppShellLayout.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measuredOverlayContent: some View {
        overlayContent
            .frame(width: Layout.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: GlobalSearchOverlayContentHeightKey.self, value: proxy.size.height)
                }
            )
            .hidden()
            .allowsHitTesting(false)
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
            HStack(spacing: AppShellLayout.spaceXS) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("最近搜索")
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                if !model.historyEntries.isEmpty {
                    Text("\(min(model.historyEntries.count, 8)) 条")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button {
                    model.clearHistory()
                } label: {
                    Text("清空")
                        .font(AppListTypography.rowCaptionEmphasized)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.historyEntries.isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
                .disabled(model.historyEntries.isEmpty)
            }
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.top, AppShellLayout.spaceXS)

            VStack(spacing: AppShellLayout.spaceXS) {
                ForEach(model.historyEntries.prefix(8)) { entry in
                    Button {
                        model.selectHistoryEntry(entry)
                    } label: {
                        GlobalSearchRecentSearchRow(
                            entry: entry,
                            isSelected: stateSelected(.recentSearch(entry.id))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, AppShellLayout.spaceXS)
    }

    private var tokenChips: some View {
        Group {
            if !state.searchTokens.isEmpty {
                HStack(spacing: 5) {
                    Text("搜索词")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary.opacity(0.72))
                    ForEach(state.searchTokens, id: \.self) { token in
                        Text(token)
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(GlobalSearchOverlayGlassStyle.chipStrokeOpacity), lineWidth: 1)
                            }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppShellLayout.spaceS)
                .padding(.vertical, 2)
            }
        }
    }

    private var actionRows: some View {
        VStack(spacing: 2) {
            GlobalSearchActionRow(kind: .newChat, query: query, isSelected: stateSelected(.action(.newChat))) {
                model.performNewChat()
            }
            GlobalSearchActionRow(kind: .webSearch, query: query, isSelected: stateSelected(.action(.webSearch))) {
                model.performWebSearch()
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(AppListTypography.rowCaption)
            .foregroundStyle(.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.vertical, AppShellLayout.spaceXS)
    }

    private func chatSessionSection(results: [GlobalSearchSessionResult]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppShellLayout.spaceXS) {
                Image(systemName: GlobalSearchSectionKind.chatSessions.systemImage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(GlobalSearchSectionKind.chatSessions.title)
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    model.showAllResults(kind: .chatSessions)
                } label: {
                    Text("查看全部 ›")
                        .font(AppListTypography.rowCaptionEmphasized)
                }
                .buttonStyle(.plain)
                .foregroundStyle(results.isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
                .disabled(query.isEmpty || results.isEmpty)
            }
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.top, AppShellLayout.spaceXS)

            if state.isSectionLoading(.chatSessions), results.isEmpty {
                GlobalSearchLoadingSourceRow()
            } else if results.isEmpty {
                GlobalSearchEmptySourceRow(title: GlobalSearchSectionKind.chatSessions.emptyTitle)
            } else if !results.isEmpty {
                VStack(spacing: 1) {
                    ForEach(results.prefix(3)) { result in
                        Button {
                            model.openChatSession(result.id)
                        } label: {
                            GlobalSearchChatSessionRow(result: result, isSelected: stateSelected(.chatSession(result.id)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minHeight: 58, alignment: .top)
        .padding(.bottom, 2)
    }

    private func browserHistorySection(results: [NativeSearchResult]) -> some View {
        let pageCount = max(1, Int(ceil(Double(results.count) / Double(browserHistoryPageSize))))
        let currentPage = min(browserHistoryPage, pageCount - 1)
        let startIndex = currentPage * browserHistoryPageSize
        let pageResults = Array(results.dropFirst(startIndex).prefix(browserHistoryPageSize))

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppShellLayout.spaceXS) {
                Image(systemName: GlobalSearchSectionKind.browserHistory.systemImage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(GlobalSearchSectionKind.browserHistory.title)
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                if !results.isEmpty {
                    Text("\(results.count) 条")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if results.count > browserHistoryPageSize {
                    browserHistoryPaginationControls(currentPage: currentPage, pageCount: pageCount)
                }
                Button {
                    model.showAllResults(kind: .browserHistory)
                } label: {
                    Text("查看全部 ›")
                        .font(AppListTypography.rowCaptionEmphasized)
                }
                .buttonStyle(.plain)
                .foregroundStyle(results.isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
                .disabled(query.isEmpty || results.isEmpty)
            }
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.top, AppShellLayout.spaceXS)

            if state.isSectionLoading(.browserHistory), pageResults.isEmpty {
                GlobalSearchLoadingSourceRow()
            } else if pageResults.isEmpty {
                GlobalSearchEmptySourceRow(title: GlobalSearchSectionKind.browserHistory.emptyTitle)
            } else if !pageResults.isEmpty {
                VStack(spacing: 1) {
                    ForEach(pageResults) { result in
                        Button {
                            model.openResult(result)
                        } label: {
                            GlobalSearchResultRow(result: result, isSelected: stateSelected(.nativeResult(result.id)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minHeight: 58, alignment: .top)
        .padding(.bottom, 2)
    }

    private func knowledgeMarketplaceSection(results: [CloudMarketplaceKnowledgeBase]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppShellLayout.spaceXS) {
                Image(systemName: GlobalSearchSectionKind.knowledgeMarketplace.systemImage)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).frame(width: 16)
                Text(GlobalSearchSectionKind.knowledgeMarketplace.title)
                    .font(AppListTypography.rowCaptionEmphasized).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("查看全部 ›") { model.showAllResults(kind: .knowledgeMarketplace) }
                    .buttonStyle(.plain)
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(results.isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
                    .disabled(query.isEmpty || results.isEmpty)
            }
            .padding(.horizontal, AppShellLayout.spaceS).padding(.top, AppShellLayout.spaceXS)

            if state.isSectionLoading(.knowledgeMarketplace), results.isEmpty {
                GlobalSearchLoadingSourceRow()
            } else if results.isEmpty {
                GlobalSearchEmptySourceRow(title: GlobalSearchSectionKind.knowledgeMarketplace.emptyTitle)
            } else {
                VStack(spacing: 1) {
                    ForEach(results.prefix(3)) { result in
                        Button { model.openKnowledgeBase(result.id) } label: {
                            HStack(spacing: AppShellLayout.spaceS) {
                                Image(systemName: "books.vertical.fill").foregroundStyle(Color.accentColor).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(AppListTypography.rowTitle).lineLimit(1)
                                    Text([result.ownerName.map { "由 \($0) 发布" }, result.owned ? "我发布的" : (result.subscribed ? "已订阅" : "未订阅")].compactMap { $0 }.joined(separator: " · "))
                                        .font(AppListTypography.rowCaption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                MarketplaceStatusBadge(base: result)
                            }
                            .padding(.horizontal, AppShellLayout.spaceS).padding(.vertical, 7)
                            .background(stateSelected(.knowledgeBase(result.id)) ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minHeight: 58, alignment: .top)
        .padding(.bottom, 2)
    }

    private func stateSelected(_ item: GlobalSearchSelectableItem) -> Bool {
        model.selectedItem == item
    }

    private func browserHistoryPaginationControls(currentPage: Int, pageCount: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                browserHistoryPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.appIcon)
            .foregroundStyle(currentPage == 0 ? Color.secondary.opacity(0.35) : Color.accentColor)
            .disabled(currentPage == 0)
            .help("上一页浏览历史")

            Text("\(currentPage + 1)/\(pageCount)")
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button {
                browserHistoryPage = min(pageCount - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.appIcon)
            .foregroundStyle(currentPage >= pageCount - 1 ? Color.secondary.opacity(0.35) : Color.accentColor)
            .disabled(currentPage >= pageCount - 1)
            .help("下一页浏览历史")
        }
    }

    private func resultSection(kind: GlobalSearchSectionKind, results: [NativeSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppShellLayout.spaceXS) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(kind.title)
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    model.showAllResults(kind: kind)
                } label: {
                    Text("查看全部 ›")
                        .font(AppListTypography.rowCaptionEmphasized)
                }
                .buttonStyle(.plain)
                .foregroundStyle(results.isEmpty ? Color.secondary.opacity(0.45) : Color.accentColor)
                .disabled(query.isEmpty || results.isEmpty)
            }
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.top, AppShellLayout.spaceXS)

            if state.isSectionLoading(kind), results.isEmpty {
                GlobalSearchLoadingSourceRow(title: state.sectionStatusMessage(kind) ?? "搜索中…")
            } else if let statusMessage = state.sectionStatusMessage(kind), results.isEmpty {
                GlobalSearchEmptySourceRow(title: statusMessage, systemImage: "info.circle")
            } else if results.isEmpty {
                GlobalSearchEmptySourceRow(title: kind.emptyTitle)
            } else if !results.isEmpty {
                VStack(spacing: 1) {
                    ForEach(results.prefix(3)) { result in
                        Button {
                            model.openResult(result)
                        } label: {
                            GlobalSearchResultRow(result: result, isSelected: stateSelected(.nativeResult(result.id)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minHeight: 58, alignment: .top)
        .padding(.bottom, 2)
    }
}

private struct GlobalSearchLoadingSourceRow: View {
    var title: String = "搜索中…"

    var body: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18)
            Text(title)
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, 8)
    }
}

private struct GlobalSearchEmptySourceRow: View {
    var title: String
    var systemImage: String = "magnifyingglass"

    var body: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            Text(title)
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, 8)
    }
}

private struct GlobalSearchRecentSearchRow: View {
    var entry: GlobalSearchHistoryEntry
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppShellLayout.spaceXS) {
                    Text(entry.query)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.searchedAt.connorLocalFormatted(date: .medium, time: .short))
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(entry.useCount > 1 ? "已搜索 \(entry.useCount) 次" : "点击恢复这次搜索")
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(isSelected ? 0.8 : 0.45))
                .padding(.top, 2)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, AppShellLayout.spaceXS)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.selectedAccentOpacity) }
        return isHovering ? Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.hoverAccentOpacity) : Color.clear
    }
}

private struct GlobalSearchActionRow: View {
    var kind: GlobalSearchActionKind
    var query: String
    var isSelected: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppShellLayout.spaceS) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                    Text(kind.subtitle(for: query))
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if kind == .newChat {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, AppShellLayout.spaceS)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.selectedAccentOpacity) }
        return isHovering ? Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.hoverAccentOpacity) : Color.clear
    }
}

private struct GlobalSearchChatSessionRow: View {
    var result: GlobalSearchSessionResult
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.indigo)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppShellLayout.spaceXS) {
                    Text(result.title.isEmpty ? "新对话" : result.title)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(result.messageCount) 条消息")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.selectedAccentOpacity) }
        return isHovering ? Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.hoverAccentOpacity) : Color.clear
    }
}

private struct GlobalSearchBrowserHistoryRow: View {
    var record: BrowserHistoryRecord

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppShellLayout.spaceXS) {
                    Text(displayTitle)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(record.visitedAt.connorLocalFormatted(date: .medium, time: .short))
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var displayTitle: String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let host = URL(string: record.url)?.host, !host.isEmpty { return host }
        return record.url
    }

    private var subtitle: String {
        let sessionTitle = record.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if sessionTitle.isEmpty { return record.url }
        return "\(record.url) · \(sessionTitle)"
    }

    private var rowBackground: Color {
        isHovering ? Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.hoverAccentOpacity) : Color.clear
    }
}

private struct GlobalSearchResultRow: View {
    var result: NativeSearchResult
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: iconName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppShellLayout.spaceXS) {
                    Text(result.title.isEmpty ? "无标题" : result.title)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !result.resultTimeLabel.isEmpty {
                        Text(result.resultTimeLabel)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppShellLayout.spaceS)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusS, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.selectedAccentOpacity) }
        return isHovering ? Color.accentColor.opacity(GlobalSearchOverlayGlassStyle.hoverAccentOpacity) : Color.clear
    }

    private var iconName: String {
        switch result.sourceKind {
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .mail: "envelope"
        case .browserHistory: "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch result.sourceKind {
        case .calendar: .purple
        case .rss: .orange
        case .mail: .blue
        case .browserHistory: .teal
        }
    }
}

private struct GlobalSearchOverlayContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
