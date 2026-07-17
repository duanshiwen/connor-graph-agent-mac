import SwiftUI
import AppKit
import ConnorGraphAppSupport

// MARK: - History Panel

struct BrowserBookmarksPanelView: View {
    @Bindable var model: BrowserFeatureModel
    var currentPageURL: String?
    var currentPageTitle: String?
    @State private var searchText: String = ""
    @State private var groupText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            searchBar
            Divider()
            groupFilterBar
            Divider()
            groupInputBar
            Divider()

            if model.filteredBookmarkRecords.isEmpty {
                emptyState
            } else {
                bookmarksList
            }

            Divider()
            footerBar
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.loadBookmarks()
            model.filterBookmarks(query: searchText, groupName: model.selectedBookmarkGroupName)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: "star.fill")
                .font(BrowserFloatingTypography.popoverTitle)
                .foregroundStyle(.secondary)
            Text("收藏夹")
                .font(BrowserFloatingTypography.popoverTitle)
            Spacer()
            Button(action: addCurrentPageToBookmarks) {
                Label(currentPageIsBookmarked ? "已收藏" : "收藏当前页", systemImage: currentPageIsBookmarked ? "checkmark" : "plus")
                    .font(AppTypography.captionEmphasis)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.accentColor.opacity(currentPageIsBookmarked ? 0.08 : 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canBookmarkCurrentPage || currentPageIsBookmarked)
            .opacity(canBookmarkCurrentPage ? 1 : 0.48)
            .help(currentPageIsBookmarked ? "当前页已在收藏夹中" : "将当前页添加到收藏夹")

            Button(action: { model.toggleBookmarksPanel() }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.appIcon)
            .help("关闭收藏夹面板")
            .accessibilityLabel("关闭收藏夹面板")
        }
        .padding(.horizontal, AppShellLayout.spaceM)
        .padding(.vertical, AppShellLayout.spaceS)
    }

    private var canBookmarkCurrentPage: Bool {
        guard let url = currentPageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return false }
        return !url.hasPrefix("connor://") && !url.hasPrefix("about:") && !url.hasPrefix("data:")
    }

    private var currentPageIsBookmarked: Bool {
        guard canBookmarkCurrentPage, let url = currentPageURL else { return false }
        return model.isBookmarked(url: url)
    }

    private func addCurrentPageToBookmarks() {
        guard canBookmarkCurrentPage, let url = currentPageURL else { return }
        model.addBookmark(
            url: url,
            title: currentPageTitle ?? "",
            groupName: model.selectedBookmarkGroupName
        )
        model.filterBookmarks(query: searchText, groupName: model.selectedBookmarkGroupName)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: "magnifyingglass")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.tertiary)
            TextField("搜索网址、标题或分组", text: $searchText)
                .textFieldStyle(.plain)
                .font(BrowserFloatingTypography.input)
                .onChange(of: searchText) { _, newValue in
                    model.filterBookmarks(query: newValue, groupName: model.selectedBookmarkGroupName)
                }
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    model.filterBookmarks(query: "", groupName: model.selectedBookmarkGroupName)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清空收藏搜索")
                .accessibilityLabel("清空收藏搜索")
            }
        }
        .padding(.horizontal, AppShellLayout.spaceM)
        .padding(.vertical, AppShellLayout.spaceS)
    }

    // MARK: - Group Filter

    private var groupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppShellLayout.spaceS) {
                groupChip(title: "全部", groupName: nil)
                ForEach(model.bookmarkGroupNames, id: \.self) { group in
                    groupChip(title: group, groupName: group)
                }
            }
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.vertical, AppShellLayout.spaceS)
        }
    }

    private func groupChip(title: String, groupName: String?) -> some View {
        let isSelected = model.selectedBookmarkGroupName == groupName
        return Button(action: {
            model.filterBookmarks(query: searchText, groupName: groupName)
        }) {
            Text(title)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var groupInputBar: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: "folder.badge.plus")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.tertiary)
            TextField("输入分组名，按 Return 切换/创建", text: $groupText)
                .textFieldStyle(.plain)
                .font(BrowserFloatingTypography.input)
                .onSubmit {
                    let trimmed = groupText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.filterBookmarks(query: searchText, groupName: trimmed)
                    groupText = ""
                }
            if model.selectedBookmarkGroupName != nil {
                Button("清除") {
                    model.filterBookmarks(query: searchText, groupName: nil)
                }
                .font(AppTypography.captionEmphasis)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppShellLayout.spaceM)
        .padding(.vertical, AppShellLayout.spaceS)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let isSearching = !searchText.isEmpty

        return VStack(spacing: AppShellLayout.spaceS) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(isSearching ? "没有找到匹配的收藏" : "还没有收藏网页")
                .font(BrowserFloatingTypography.hint.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(isSearching ? "可以换个关键词，或者查看全部收藏。" : "遇到想反复查看的资料，可以点星标收藏。康纳同学会把它留在这个工作区里，方便之后继续阅读和提问。")
                .font(AppTypography.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, AppShellLayout.spaceL)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    private var groupedRecords: [BrowserBookmarkGroup] {
        BrowserBookmarkGrouper().group(model.filteredBookmarkRecords)
    }

    private var bookmarksList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedRecords) { group in
                    sectionHeader(group.label)
                    ForEach(group.records) { record in
                        BrowserBookmarkRow(record: record) {
                            model.navigateToBookmark(record)
                        } onDelete: {
                            model.deleteBookmark(record.id)
                            model.filterBookmarks(query: searchText, groupName: model.selectedBookmarkGroupName)
                        }
                    }
                }
            }
            .padding(.vertical, AppShellLayout.spaceS)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.top, AppShellLayout.spaceM)
            .padding(.bottom, AppShellLayout.spaceXS)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text("\(model.filteredBookmarkRecords.count) 个收藏")
                .font(AppTypography.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(model.selectedBookmarkGroupName ?? "全部分组")
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppShellLayout.spaceM)
        .padding(.vertical, AppShellLayout.spaceS)
    }
}

// MARK: - Bookmark Row

struct BrowserBookmarkRow: View {
    var record: BrowserBookmarkRecord
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppShellLayout.spaceS) {
                favicon
                VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                    Text(displayTitle)
                        .font(BrowserFloatingTypography.pageTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(displayURL)
                        .font(BrowserFloatingTypography.pageURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: AppShellLayout.spaceXS)
                VStack(alignment: .trailing, spacing: AppShellLayout.spaceXS) {
                    Text(record.groupName)
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                    Text(timeString)
                        .font(AppTypography.monoMicro.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.vertical, AppShellLayout.spaceS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.secondary.opacity(0.06) : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("删除此收藏", role: .destructive, action: onDelete)
            Divider()
            Button("复制网址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.url, forType: .string)
            }
        }
        .help(record.url)
    }

    private var displayTitle: String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (URL(string: record.url)?.host ?? record.url) : title
    }

    private var displayURL: String {
        if let url = URL(string: record.url), let host = url.host {
            return host + (url.path == "/" ? "" : url.path)
        }
        return record.url
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "M/d"
        return formatter.string(from: record.updatedAt)
    }

    @ViewBuilder
    private var favicon: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            default:
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var faviconURL: URL? {
        guard let host = URL(string: record.url)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}

// MARK: - Grouping

struct BrowserBookmarkGroup: Identifiable {
    let id: String
    let label: String
    let records: [BrowserBookmarkRecord]
}

struct BrowserBookmarkGrouper {
    func group(_ records: [BrowserBookmarkRecord]) -> [BrowserBookmarkGroup] {
        let sorted = records.sorted { lhs, rhs in
            if lhs.groupName == rhs.groupName { return lhs.updatedAt > rhs.updatedAt }
            if lhs.groupName == BrowserBookmarkRecord.defaultGroupName { return true }
            if rhs.groupName == BrowserBookmarkRecord.defaultGroupName { return false }
            return lhs.groupName.localizedStandardCompare(rhs.groupName) == .orderedAscending
        }

        var groups: [(label: String, records: [BrowserBookmarkRecord])] = []
        for record in sorted {
            let label = record.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BrowserBookmarkRecord.defaultGroupName : record.groupName
            if let index = groups.firstIndex(where: { $0.label == label }) {
                groups[index].records.append(record)
            } else {
                groups.append((label: label, records: [record]))
            }
        }

        return groups.map { BrowserBookmarkGroup(id: $0.label, label: $0.label, records: $0.records) }
    }
}
