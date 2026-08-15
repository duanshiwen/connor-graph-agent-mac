import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CloudKnowledgeMarketplaceListPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @ObservedObject var creatorStore: CloudKnowledgeCreatorStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    var sessions: [AgentSession]
    let sessionActions: any ChatSessionCommanding
    @State private var isPresentingCreator = false
    @State private var isPresentingPublicationHistory = false
    /// 主列表头筛选：全部知识库 / 我订阅的 / 我创建的。
    @State private var listFilter: MarketplaceListFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("知识市场")
                    .font(AppListTypography.header)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: AppShellLayout.spaceS) {
                    filterMenu
                    Spacer(minLength: 0)
                    Button { isPresentingPublicationHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.appIcon)
                    .help("发布历史")
                    .accessibilityLabel("发布历史")
                    .disabled(!canUseMarketplace)
                    Button {
                        creatorStore.prepareForNewKnowledgeBase()
                        isPresentingCreator = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.appIcon)
                    .help("添加知识库")
                    .accessibilityLabel("添加知识库")
                    .disabled(!canUseMarketplace)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppShellLayout.paneHeaderHorizontalPadding)
            .padding(.vertical, AppShellLayout.paneHeaderVerticalPadding)

            if canUseMarketplace {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppListCardLayout.spacing) {
                        if listFilter != .all {
                            marketplaceFilterBanner
                        }
                        if unifiedBases.isEmpty {
                            ContentUnavailableView(marketplaceEmptyTitle, systemImage: "books.vertical", description: Text(marketplaceEmptyDescription))
                                .padding(.top, 80)
                        } else {
                            ForEach(unifiedBases) { base in
                                libraryRow(base)
                                    .onAppear {
                                        // 分页由“市场搜索结果”驱动：滚到当前搜索结果最后一条时加载下一页。
                                        if store.searchResults.last?.id == base.id {
                                            Task { await store.loadMoreSearchResultsIfNeeded(currentID: base.id) }
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, AppListCardLayout.horizontalInset)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
                .scrollContentBackground(.hidden)
            } else {
                Label(marketplaceUnavailableTitle, systemImage: marketplaceUnavailableSystemImage)
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppListCardLayout.horizontalInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.showHome() }
        .task { if canUseMarketplace, store.home.categories.isEmpty { await store.load() } }
        .onChange(of: connectivity.isConnected) { _, isConnected in
            if isConnected { Task { await store.load() } }
            else { store.showHome() }
        }
        .onChange(of: backendConnectivity.state) { _, state in
            if state == .reachable { Task { await store.load() } }
            else if state == .unreachable { store.showHome() }
        }
        .sheet(isPresented: $isPresentingCreator) {
            VStack(spacing: 0) {
                HStack {
                    Text("添加知识库").font(AppListTypography.header)
                    Spacer()
                    Button { isPresentingCreator = false } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.appIcon)
                    .help("关闭")
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider()
                CloudKnowledgeCreatorView(
                    store: creatorStore,
                    sessions: sessions,
                    loadSessionPage: { await sessionActions.loadChatSessionPickerPage(cursor: $0) }
                ) { knowledgeBaseID in
                    isPresentingCreator = false
                    Task {
                        await store.load()
                        await store.loadDetail(id: knowledgeBaseID)
                    }
                }
            }
            .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $isPresentingPublicationHistory) {
            KnowledgePublicationHistoryView(store: creatorStore) {
                isPresentingPublicationHistory = false
                isPresentingCreator = true
            }
        }
    }

    private func libraryRow(_ base: CloudMarketplaceKnowledgeBase) -> some View {
        marketplaceRow(base: base, isSelected: store.selected?.id == base.id) {
            Task { await store.loadDetail(id: base.id) }
        }
    }

    /// 单一列表行：标题 + 元信息副标题，右侧用彩色胶囊徽标标记状态
    /// （我发布的 / 未发布 / 已订阅，市场默认无徽标）。
    private func marketplaceRow(
        base: CloudMarketplaceKnowledgeBase,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: AppListCardLayout.contentSpacing) {
                    Text(base.name.isEmpty ? "未命名知识库" : base.name)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .lineLimit(AppListCardLayout.titleLineLimit)
                    Text(marketplaceCaption(base))
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                MarketplaceRowStatusBadges(base: base)
            }
            .appListRowSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// 卡片副标题：订阅者数、发布者等元信息；状态由徽标承载，避免文字重复。
    private func marketplaceCaption(_ base: CloudMarketplaceKnowledgeBase) -> String {
        var parts: [String] = []
        if base.subscriberCount > 0 { parts.append("\(base.subscriberCount) 位订阅者") }
        if !base.owned, let owner = base.ownerName, !owner.isEmpty { parts.append("由 \(owner) 发布") }
        if base.owned, !base.isPublished { parts.append("尚未发布到知识市场") }
        return parts.isEmpty ? "知识库" : parts.joined(separator: " · ")
    }

    private var unifiedBases: [CloudMarketplaceKnowledgeBase] { store.unifiedBases(filter: listFilter) }

    /// 列表为空时的统一空状态（与其它列表面板一致使用 ContentUnavailableView），
    /// 文案按当前筛选维度区分。
    private var marketplaceEmptyTitle: String {
        switch listFilter {
        case .subscribed: "还没有订阅知识库"
        case .owned: "还没有创建知识库"
        case .all: "暂无可用知识库"
        }
    }

    private var marketplaceEmptyDescription: String {
        switch listFilter {
        case .subscribed: "在知识市场浏览并订阅感兴趣的知识库后，会显示在这里。"
        case .owned: "点击右上角 + 新建并发布知识库后，会显示在这里。"
        case .all: "知识市场用于发现、订阅并使用社区发布的结构化知识库。"
        }
    }

    /// 主列表头左侧筛选按钮：切换「全部知识库 / 我订阅的 / 我创建的」。
    /// 视觉与“发布历史 / 添加知识库”图标按钮保持一致（同字号、同圆形背景、隐藏菜单指示器）。
    private var filterMenu: some View {
        Menu {
            ForEach(MarketplaceListFilter.allCases) { option in
                Button {
                    listFilter = option
                } label: {
                    if option == listFilter {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: AppButtonLayout.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: AppButtonLayout.iconButtonSize, height: AppButtonLayout.iconButtonSize)
                .contentShape(Circle())
                .background(Color.secondary.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("筛选知识库：\(listFilter.title)")
        .accessibilityLabel("筛选知识库")
    }

    /// 主列表顶部的筛选提示栏：仅当筛选条件不是「全部知识库」时出现，
    /// 用一个小型胶囊提示当前筛选，并可直接一键清除恢复全部。
    private var marketplaceFilterBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("正在筛选：")
                .font(AppListTypography.rowCaption)
                .foregroundStyle(.secondary)
            Text(listFilter.title)
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                listFilter = .all
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("清除筛选，查看全部知识库")
            .accessibilityLabel("清除筛选")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canUseMarketplace: Bool { connectivity.isConnected && backendConnectivity.state != .unreachable }
    private var marketplaceUnavailableTitle: String { connectivity.isConnected ? "当前无法连接到康纳服务器" : "当前没有网络连接" }
    private var marketplaceUnavailableSystemImage: String { connectivity.isConnected ? "exclamationmark.icloud" : "wifi.slash" }
}

struct CloudKnowledgeMarketplaceDetailPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @ObservedObject var creatorStore: CloudKnowledgeCreatorStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    var sessions: [AgentSession]
    let sessionActions: any ChatSessionCommanding
    @State private var selectedCategoryID: String?
    @State private var isPresentingEditor = false
    @State private var isConfirmingDelete = false
    @State private var isPresentingPublishingAgreement = false
    @State private var actionErrorMessage: String?

    var body: some View {
        Group {
            if !canUseMarketplace {
                unavailableMarketplaceHome
            } else if let selected = store.selected {
                marketplaceDetail(selected)
            } else {
                marketplaceHome
            }
        }
        .background(AppShellColors.detailBackground)
        .sheet(isPresented: $isPresentingEditor) {
            VStack(spacing: 0) {
                HStack {
                    Text("编辑知识库").font(AppListTypography.header)
                    Spacer()
                    Button { isPresentingEditor = false } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.appIcon)
                    .help("关闭")
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider()
                CloudKnowledgeCreatorView(
                    store: creatorStore,
                    sessions: sessions,
                    loadSessionPage: { await sessionActions.loadChatSessionPickerPage(cursor: $0) }
                ) { knowledgeBaseID in
                    isPresentingEditor = false
                    Task {
                        await store.load()
                        await store.loadDetail(id: knowledgeBaseID)
                    }
                }
            }
            .frame(minWidth: 760, idealWidth: 840, minHeight: 620, idealHeight: 700)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $isPresentingPublishingAgreement) {
            KnowledgeBasePublishingAgreementSheet {
                Task {
                    if let id = await creatorStore.publishKnowledgeBase(termsAccepted: true) {
                        actionErrorMessage = nil
                        await store.load()
                        await store.loadDetail(id: id)
                    } else {
                        actionErrorMessage = creatorStore.errorMessage ?? "发布失败，请稍后重试"
                    }
                }
            }
        }
        .confirmationDialog("删除知识库？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除知识库", role: .destructive) {
                guard let base = store.selected else { return }
                Task {
                    actionErrorMessage = nil
                    await creatorStore.requestDeleteKnowledgeBase(id: base.id, reason: "owner requested deletion")
                    if let error = creatorStore.errorMessage {
                        // 删除请求失败（有订阅者/无权限/后端异常等）：留在详情页并提示原因，不再假删除。
                        actionErrorMessage = error
                    } else {
                        store.showHome()
                        await store.load()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后知识库将进入删除流程并停止对外提供服务（已发布状态会被撤销）。此操作不可撤销。")
        }
        .onChange(of: connectivity.isConnected) { _, isConnected in
            guard isConnected else { return }
            store.showHome()
            Task { await store.load() }
        }
        .onChange(of: backendConnectivity.state) { _, state in
            guard state == .reachable else { return }
            store.showHome()
            Task { await store.load() }
        }
    }

    private var unavailableMarketplaceHome: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("KnowledgeMarketplacePoster")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 1120)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("知识市场即将开放")

                Label(marketplaceUnavailableTitle, systemImage: marketplaceUnavailableSystemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(marketplaceUnavailableDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canUseMarketplace: Bool { connectivity.isConnected && backendConnectivity.state != .unreachable }
    private var marketplaceUnavailableTitle: String { connectivity.isConnected ? "当前无法连接到康纳服务器" : "当前没有网络连接" }
    private var marketplaceUnavailableSystemImage: String { connectivity.isConnected ? "exclamationmark.icloud" : "wifi.slash" }
    private var marketplaceUnavailableDescription: String {
        let recovery = connectivity.isConnected ? "服务器恢复后" : "网络恢复后"
        return "知识市场用于发现、订阅并使用社区发布的结构化知识库。\(recovery)将自动加载首页内容。"
    }

    private var marketplaceHome: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("知识市场").font(AppTypography.pageTitle)
                    Text("发现、订阅并使用社区发布的结构化知识库").foregroundStyle(.secondary)
                }

                if !store.home.categories.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            categoryButton("全部", id: nil, systemImage: "square.grid.2x2")
                            ForEach(store.home.categories) { category in
                                categoryButton(category.name, id: category.id, systemImage: category.icon ?? "folder")
                            }
                        }
                    }
                }

                if !store.searchResults.isEmpty {
                    marketplaceSection(title: marketplaceBrowseTitle, bases: store.searchResults)
                }

                if store.searchResults.isEmpty && !store.isLoading {
                    ContentUnavailableView("暂无可用知识库", systemImage: "books.vertical", description: Text("当前分类下还没有已发布的知识库。"))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
                if store.isLoading { ProgressView("正在加载知识市场…").frame(maxWidth: .infinity) }
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(28)
        }
        .task { if canUseMarketplace, store.home.categories.isEmpty { await store.load() } }
    }

    private func marketplaceSection(title: String, bases: [CloudMarketplaceKnowledgeBase]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(AppTypography.sectionTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(bases) { base in
                    Button { Task { await store.loadDetail(id: base.id) } } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Color.accentColor)
                                Spacer()
                                MarketplaceStatusBadge(base: base)
                            }
                            Text(base.name).font(.headline).lineLimit(1)
                            Text(base.description ?? "暂无介绍").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            Text(base.ownerName.map { "由 \($0) 发布" } ?? "社区知识库").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func categoryButton(_ title: String, id: String?, systemImage: String) -> some View {
        Button {
            selectedCategoryID = id
            Task { await store.search(query: "", categoryID: id) }
        } label: {
            Label(title, systemImage: systemImage).padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    private var marketplaceBrowseTitle: String {
        guard let selectedCategoryID,
              let category = store.home.categories.first(where: { $0.id == selectedCategoryID })
        else { return "全部知识库" }
        return category.name
    }

    private func marketplaceDetail(_ base: CloudMarketplaceKnowledgeBase) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { store.showHome() } label: { Label("返回知识市场", systemImage: "chevron.left") }.buttonStyle(.plain)
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 48)).foregroundStyle(Color.accentColor).frame(width: 72, height: 72)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(base.name).font(AppTypography.pageTitle); MarketplaceStatusBadge(base: base) }
                        Text(base.ownerName.map { "由 \($0) 发布" } ?? "社区知识库").foregroundStyle(.secondary)
                        Text("\(base.subscriberCount) 位订阅者").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        // 订阅类主操作：已订阅（含自己订阅自己）显示“取消订阅”；未订阅且可订阅（已发布）时显示强调色“订阅”。
                        // 自己创建并已发布的知识库同样可以订阅自己（后端 v2 仅校验 published/active/clear，不限制所有者）。
                        if base.subscribed {
                            Button("取消订阅") { Task { await store.unsubscribe(id: base.id) } }
                                .buttonStyle(.bordered)
                        } else if !base.owned || base.publicationStatus == "published" {
                            Button("订阅") { Task { await store.subscribe(id: base.id) } }
                                .buttonStyle(.borderedProminent)
                        }
                        // 所有者管理组：编辑 · 下架（仅已发布） · 删除，次要操作成组、破坏性操作放组尾并需确认。
                        if base.owned {
                            HStack(spacing: 8) {
                                if base.publicationStatus != "published" {
                                    Button("发布到市场") {
                                        Task {
                                            actionErrorMessage = nil
                                            await creatorStore.prepareForEdit(id: base.id)
                                            isPresentingPublishingAgreement = true
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .help("发布到知识市场前需同意发布协议")
                                }
                                Button("编辑") {
                                    Task {
                                        await creatorStore.prepareForEdit(id: base.id)
                                        isPresentingEditor = true
                                    }
                                }
                                .buttonStyle(.bordered)
                                if base.publicationStatus == "published" {
                                    Button("下架") {
                                        Task {
                                            actionErrorMessage = nil
                                            await creatorStore.prepareForEdit(id: base.id)
                                            await creatorStore.unpublishKnowledgeBase()
                                            if let error = creatorStore.errorMessage {
                                                // 后端拒绝（如已有订阅者）时留在详情页并提示原因。
                                                actionErrorMessage = error
                                                await store.loadDetail(id: base.id)
                                            } else {
                                                await store.load()
                                                await store.loadDetail(id: base.id)
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(base.subscriberCount > 0)
                                    .help(base.subscriberCount > 0 ? "有 \(base.subscriberCount) 位订阅者，暂不能下架；知识库是持续系统，只能持续更新" : "下架后知识库不再对外提供服务")
                                }
                                Button("删除", role: .destructive) { isConfirmingDelete = true }
                                    .buttonStyle(.bordered)
                                    .disabled(base.subscriberCount > 0)
                                    .help(base.subscriberCount > 0 ? "有 \(base.subscriberCount) 位订阅者，暂不能删除；知识库是持续系统，只能持续更新" : "删除知识库")
                            }
                            if let actionErrorMessage {
                                Label(actionErrorMessage, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                Divider()
                Text("关于此知识库").font(AppTypography.sectionTitle)
                Text(base.description ?? "发布者暂未提供详细介绍。").font(.body)
                if let category = base.categoryID { Label(category, systemImage: "folder").foregroundStyle(.secondary) }
                if store.isLoading { ProgressView() }
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(32)
        }
    }
}

struct MarketplaceStatusBadge: View {
    var base: CloudMarketplaceKnowledgeBase

    var body: some View {
        HStack(spacing: 5) {
            // 所有权优先：已发布/未发布；订阅作为可叠加的次要状态。
            if base.owned {
                badge(
                    base.isPublished ? "我发布的" : "未发布",
                    color: base.isPublished ? Color.accentColor : .orange
                )
            }
            if base.subscribed {
                badge("已订阅", color: .green)
            } else if !base.owned {
                badge("未订阅", color: .secondary)
            }
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// 列表卡片右侧的状态徽标组：所有权徽标（我发布的 / 未发布）与“已订阅”可叠加；
/// 市场默认（未订阅且非我发布）不显示徽标，保持列表干净。
private struct MarketplaceRowStatusBadges: View {
    var base: CloudMarketplaceKnowledgeBase

    var body: some View {
        HStack(spacing: 5) {
            if base.owned {
                MarketplaceRowStatusBadge(
                    title: base.isPublished ? "我发布的" : "未发布",
                    color: base.isPublished ? Color.accentColor : .orange
                )
            }
            if base.subscribed {
                MarketplaceRowStatusBadge(title: "已订阅", color: .green)
            }
        }
    }
}

private struct MarketplaceRowStatusBadge: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

/// 详情页直接发布前的协议确认对话框：展示《知识库发布协议》，
/// 勾选“我已阅读并同意”后“同意并发布”才可用。
private struct KnowledgeBasePublishingAgreementSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAgree: () -> Void
    @State private var termsAccepted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CloudKnowledgePublishingAgreement.title)
                        .font(AppTypography.pageTitle)
                    Text("版本 \(CloudKnowledgePublishingAgreement.version) · \(CloudKnowledgePublishingAgreement.effectiveDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭发布协议")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(CloudKnowledgePublishingAgreement.operatorName, systemImage: "building.2")
                        .font(.headline)

                    ForEach(CloudKnowledgePublishingAgreement.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()

            HStack {
                Toggle("", isOn: $termsAccepted)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("我已阅读并同意知识库发布协议")
                Text("我已阅读并同意《\(CloudKnowledgePublishingAgreement.title)》")
                    .font(.callout)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("同意并发布") {
                    onAgree()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!termsAccepted)
            }
            .padding(16)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
