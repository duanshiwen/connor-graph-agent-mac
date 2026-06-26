import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct AppGlobalSearchOverlayView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var browserHistoryPage: Int = 0

    private let browserHistoryPageSize = 3
    private var state: GlobalSearchPreviewState { viewModel.globalSearchPreviewState }
    private var query: String { viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                actionRows
                tokenChips

                chatSessionSection(results: state.chatSessionResults)
                resultSection(kind: .mail, results: state.mailResults)
                resultSection(kind: .calendar, results: state.calendarResults)
                resultSection(kind: .rss, results: state.rssResults)
                browserHistorySection(results: state.browserHistoryResults)

                if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                    errorRow(errorMessage)
                }
            }
            .padding(AppShellLayout.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .frame(width: 640, alignment: .topLeading)
        .frame(maxHeight: 760, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
        .onChange(of: state.query) { _, _ in
            browserHistoryPage = 0
        }
    }

    private var tokenChips: some View {
        Group {
            if !state.searchTokens.isEmpty {
                HStack(spacing: 5) {
                    Text("搜索词")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                    ForEach(state.searchTokens, id: \.self) { token in
                        Text(token)
                            .font(AppListTypography.rowCaptionEmphasized)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
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
                viewModel.performGlobalSearchNewChat()
            }
            GlobalSearchActionRow(kind: .webSearch, query: query, isSelected: stateSelected(.action(.webSearch))) {
                viewModel.performGlobalSearchWebSearch()
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
                    viewModel.showAllGlobalSearchResults(kind: .chatSessions)
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
                            viewModel.openGlobalSearchChatSessionResult(result.id)
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
                    viewModel.showAllGlobalSearchResults(kind: .browserHistory)
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
                            viewModel.openGlobalSearchResult(result)
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

    private func stateSelected(_ item: GlobalSearchSelectableItem) -> Bool {
        viewModel.globalSearchSelectedItem == item
    }

    private func browserHistoryPaginationControls(currentPage: Int, pageCount: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                browserHistoryPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
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
                    viewModel.showAllGlobalSearchResults(kind: kind)
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
                GlobalSearchLoadingSourceRow()
            } else if results.isEmpty {
                GlobalSearchEmptySourceRow(title: kind.emptyTitle)
            } else if !results.isEmpty {
                VStack(spacing: 1) {
                    ForEach(results.prefix(3)) { result in
                        Button {
                            viewModel.openGlobalSearchResult(result)
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
    var body: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18)
            Text("搜索中…")
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

    var body: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: "magnifyingglass")
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
        if isSelected { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.accentColor.opacity(0.08) : Color.clear
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
        if isSelected { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.accentColor.opacity(0.08) : Color.clear
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
                    Text(record.visitedAt.formatted(date: .abbreviated, time: .shortened))
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
        isHovering ? Color.accentColor.opacity(0.08) : Color.clear
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
        if isSelected { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.accentColor.opacity(0.08) : Color.clear
    }

    private var iconName: String {
        switch result.sourceKind {
        case .mail: "envelope"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .browserHistory: "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch result.sourceKind {
        case .mail: .blue
        case .calendar: .purple
        case .rss: .orange
        case .browserHistory: .teal
        }
    }
}
