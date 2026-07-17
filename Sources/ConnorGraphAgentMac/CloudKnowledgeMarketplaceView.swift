import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CloudKnowledgeMarketplaceListPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @ObservedObject var creatorStore: CloudKnowledgeCreatorStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    var sessions: [AgentSession]
    @State private var isPresentingCreator = false
    @State private var isPresentingPublicationHistory = false

    var body: some View {
        VStack(spacing: 0) {
            AppListPaneHeader(title: "知识市场") {
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

            if canUseMarketplace {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppListCardLayout.spacing) {
                        marketplaceSectionHeader("已订阅")
                        if store.library.subscribed.isEmpty {
                            emptyRow("暂未订阅知识库")
                        } else {
                            ForEach(store.library.subscribed) { base in
                                libraryRow(base, caption: base.owned ? "我发布的 · 已订阅" : "已订阅")
                            }
                        }

                        marketplaceSectionHeader("我发布的")
                        if store.library.owned.isEmpty {
                            emptyRow("暂未发布知识库")
                        } else {
                            ForEach(store.library.owned) { base in
                                libraryRow(
                                    base,
                                    caption: base.subscribed
                                        ? "\(publicationLabel(base)) · 已订阅"
                                        : publicationLabel(base)
                                )
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
                CloudKnowledgeCreatorView(store: creatorStore, sessions: sessions) { knowledgeBaseID in
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

    private func libraryRow(_ base: CloudMarketplaceKnowledgeBase, caption: String) -> some View {
        marketplaceRow(
            title: base.name,
            caption: caption,
            systemImage: "books.vertical",
            isSelected: store.selected?.id == base.id
        ) {
            Task { await store.loadDetail(id: base.id) }
        }
    }

    private func marketplaceRow(
        title: String,
        caption: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .lineLimit(AppListCardLayout.titleLineLimit)
                    Text(caption)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .appListRowSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(AppListTypography.rowCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marketplaceSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func publicationLabel(_ base: CloudMarketplaceKnowledgeBase) -> String {
        base.publicationStatus == "published" ? "已发布" : "未发布"
    }

    private var canUseMarketplace: Bool { connectivity.isConnected && backendConnectivity.state != .unreachable }
    private var marketplaceUnavailableTitle: String { connectivity.isConnected ? "当前无法连接到康纳服务器" : "当前没有网络连接" }
    private var marketplaceUnavailableSystemImage: String { connectivity.isConnected ? "exclamationmark.icloud" : "wifi.slash" }
}

struct CloudKnowledgeMarketplaceDetailPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    @State private var selectedCategoryID: String?

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
        ContentUnavailableView {
            Label(marketplaceUnavailableTitle, systemImage: marketplaceUnavailableSystemImage)
        } description: {
            Text(marketplaceUnavailableDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
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
                    if base.subscribed {
                        Button("取消订阅") { Task { await store.unsubscribe(id: base.id) } }
                            .buttonStyle(.bordered)
                    } else {
                        Button("订阅") { Task { await store.subscribe(id: base.id) } }
                            .buttonStyle(.borderedProminent)
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
            if base.owned { badge("我发布的", emphasized: true) }
            if base.subscribed {
                badge("已订阅", emphasized: true)
            } else if !base.owned {
                badge("未订阅", emphasized: false)
            }
        }
    }

    private func badge(_ title: String, emphasized: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((emphasized ? Color.accentColor : Color.secondary).opacity(0.1), in: Capsule())
    }
}
