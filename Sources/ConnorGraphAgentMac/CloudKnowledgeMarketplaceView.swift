import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CloudKnowledgeMarketplaceListPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("知识市场").font(.headline)
                Spacer()
                Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新知识市场")
            }
            .padding(12)

            List {
                Section {
                    Button { store.showHome() } label: {
                        Label("市场首页", systemImage: "storefront")
                    }
                    Button { store.showPublisher() } label: {
                        Label("发布知识库", systemImage: "plus.square.on.square")
                    }
                }

                Section("已订阅") {
                    if store.library.subscribed.isEmpty {
                        Text("暂未订阅知识库").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.library.subscribed) { base in libraryRow(base, badge: "已订阅") }
                    }
                }

                Section("我发布的") {
                    if store.library.owned.isEmpty {
                        Text("暂未发布知识库").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.library.owned) { base in libraryRow(base, badge: publicationLabel(base)) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .task { if store.home.categories.isEmpty { await store.load() } }
    }

    private func libraryRow(_ base: CloudMarketplaceKnowledgeBase, badge: String) -> some View {
        Button { Task { await store.loadDetail(id: base.id) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(base.name).lineLimit(1)
                Text(badge).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func publicationLabel(_ base: CloudMarketplaceKnowledgeBase) -> String {
        base.publicationStatus == "published" ? "已发布" : "未发布"
    }
}

struct CloudKnowledgeMarketplaceDetailPane: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @ObservedObject var creatorStore: CloudKnowledgeCreatorStore
    var sessions: [AgentSession]

    var body: some View {
        Group {
            if store.showsPublisher {
                ScrollView {
                    CloudKnowledgeCreatorView(store: creatorStore, sessions: sessions)
                        .frame(maxWidth: 760)
                        .padding(24)
                }
            } else if let selected = store.selected {
                marketplaceDetail(selected)
            } else {
                marketplaceHome
            }
        }
        .background(AppShellColors.detailBackground)
    }

    private var marketplaceHome: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("知识市场").font(.largeTitle.bold())
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
                    marketplaceSection(title: "搜索结果", bases: store.searchResults)
                }
                ForEach(store.home.sections) { section in
                    marketplaceSection(title: section.title, bases: section.knowledgeBases)
                }

                if store.home.sections.isEmpty && !store.isLoading {
                    ContentUnavailableView("暂无推荐内容", systemImage: "books.vertical", description: Text("可以通过分类或统一搜索查找知识库。"))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
                if store.isLoading { ProgressView("正在加载知识市场…").frame(maxWidth: .infinity) }
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(28)
        }
        .task { if store.home.categories.isEmpty { await store.load() } }
    }

    private func marketplaceSection(title: String, bases: [CloudMarketplaceKnowledgeBase]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
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
        Button { Task { await store.search(query: "", categoryID: id) } } label: {
            Label(title, systemImage: systemImage).padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
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
                        HStack { Text(base.name).font(.largeTitle.bold()); MarketplaceStatusBadge(base: base) }
                        Text(base.ownerName.map { "由 \($0) 发布" } ?? "社区知识库").foregroundStyle(.secondary)
                        Text("\(base.subscriberCount) 位订阅者").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !base.owned {
                        if base.subscribed {
                            Button("取消订阅") { Task { await store.unsubscribe(id: base.id) } }
                                .buttonStyle(.bordered)
                        } else {
                            Button("订阅") { Task { await store.subscribe(id: base.id) } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                Divider()
                Text("关于此知识库").font(.title2.bold())
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
        Text(base.owned ? "我发布的" : (base.subscribed ? "已订阅" : "未订阅"))
            .font(.caption.weight(.medium))
            .foregroundStyle(base.owned || base.subscribed ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((base.owned || base.subscribed ? Color.accentColor : Color.secondary).opacity(0.1), in: Capsule())
    }
}
