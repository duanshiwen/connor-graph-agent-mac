import SwiftUI
import ConnorGraphAppSupport

struct CloudKnowledgeMarketplaceView: View {
    @ObservedObject var store: CloudKnowledgeMarketplaceStore
    @State private var query = ""
    @State private var selectedCategoryID: String?

    var body: some View {
        SettingsGroup(title: "知识库商城") {
            VStack(alignment: .leading, spacing: 14) {
                HStack { TextField("搜索知识库", text: $query).textFieldStyle(.roundedBorder).onSubmit { Task { await store.search(query: query, categoryID: selectedCategoryID) } }; Button("搜索") { Task { await store.search(query: query, categoryID: selectedCategoryID) } } }
                if !store.home.categories.isEmpty { ScrollView(.horizontal) { HStack { Button("全部") { selectedCategoryID = nil; Task { await store.search(query: query) } }; ForEach(store.home.categories) { category in Button(category.name) { selectedCategoryID = category.id; Task { await store.search(query: query, categoryID: category.id) } } } } } }
                ForEach(store.home.banners) { banner in VStack(alignment: .leading, spacing: 3) { Text(banner.title).font(.headline); if let subtitle = banner.subtitle { Text(subtitle).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)) }
                if !store.searchResults.isEmpty { marketplaceRows(title: "搜索结果", bases: store.searchResults) }
                ForEach(store.home.sections) { section in marketplaceRows(title: section.title, bases: section.knowledgeBases) }
                if let selected = store.selected { Divider(); VStack(alignment: .leading, spacing: 8) { Text(selected.name).font(.headline); Text(selected.description ?? "暂无介绍").foregroundStyle(.secondary); Text("\(selected.subscriberCount) 位订阅者").font(.caption); Button(selected.subscribed ? "取消订阅" : "订阅") { Task { selected.subscribed ? await store.unsubscribe(id: selected.id) : await store.subscribe(id: selected.id) } }.buttonStyle(.borderedProminent) } }
                if store.isLoading { ProgressView("正在加载商城…") }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .task { await store.loadHome() }
        }
    }

    private func marketplaceRows(title: String, bases: [CloudMarketplaceKnowledgeBase]) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); ForEach(bases) { base in Button { Task { await store.loadDetail(id: base.id) } } label: { HStack { VStack(alignment: .leading) { Text(base.name); if let description = base.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }; Spacer(); if base.subscribed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } } }.buttonStyle(.plain); Divider() } }
    }
}
