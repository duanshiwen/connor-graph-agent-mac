import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Cloud Knowledge Marketplace Unified List Tests")
struct CloudKnowledgeMarketplaceListTests {
    @Test func marketplaceCardStatusMapsAllStates() {
        #expect(CloudMarketplaceKnowledgeBase(id: "a", name: "Published", owned: true, publicationStatus: "published").marketplaceCardStatus == .published)
        #expect(CloudMarketplaceKnowledgeBase(id: "b", name: "Draft", owned: true, publicationStatus: "unpublished").marketplaceCardStatus == .unpublished)
        #expect(CloudMarketplaceKnowledgeBase(id: "c", name: "Draft nil", owned: true, publicationStatus: nil).marketplaceCardStatus == .unpublished)
        #expect(CloudMarketplaceKnowledgeBase(id: "d", name: "Subscribed", subscribed: true).marketplaceCardStatus == .subscribed)
        #expect(CloudMarketplaceKnowledgeBase(id: "e", name: "Market").marketplaceCardStatus == .market)
        // 自己发布并订阅：所有权优先，主状态仍是“我发布的”。
        #expect(CloudMarketplaceKnowledgeBase(id: "f", name: "Owned+Sub", subscribed: true, owned: true, publicationStatus: "published").marketplaceCardStatus == .published)
        #expect(CloudMarketplaceKnowledgeBase(id: "g", name: "Draft+Sub", subscribed: true, owned: true, publicationStatus: nil).marketplaceCardStatus == .unpublished)
    }

    @Test func unifiedListDedupesAndOrdersByStatus() {
        let library = CloudMarketplaceLibrary(
            subscribed: [
                .init(id: "sub-1", name: "已订阅一", subscribed: true, ownerName: "Alice"),
                .init(id: "both", name: "我发布并订阅", subscribed: true, owned: true, publicationStatus: "published"),
            ],
            owned: [
                .init(id: "owned-draft", name: "草稿", owned: true, publicationStatus: "unpublished"),
                .init(id: "both", name: "我发布并订阅", owned: true, publicationStatus: "published"),
                .init(id: "owned-pub", name: "已发布", owned: true, publicationStatus: "published"),
            ]
        )
        let searchResults: [CloudMarketplaceKnowledgeBase] = [
            .init(id: "market-1", name: "市场一", categoryID: "agents"),
            .init(id: "both", name: "我发布并订阅", categoryID: "productivity"),
        ]

        let list = library.unifiedList(searchResults: searchResults)

        // 顺序：我发布的（已发布 → 未发布）→ 已订阅 → 市场；同一 id 只出现一次。
        #expect(list.map(\.id) == ["both", "owned-pub", "owned-draft", "sub-1", "market-1"])
        // “both” 合并了三个来源的字段：subscribed/owned 并集 + category 互补。
        let merged = list.first { $0.id == "both" }
        #expect(merged?.subscribed == true)
        #expect(merged?.owned == true)
        #expect(merged?.categoryID == "productivity")
    }

    @Test func unifiedListKeepsPublishedBeforeUnpublishedWithinOwned() {
        let library = CloudMarketplaceLibrary(
            owned: [
                .init(id: "draft", name: "草稿", owned: true, publicationStatus: nil),
                .init(id: "pub", name: "已发布", owned: true, publicationStatus: "published"),
            ]
        )
        let list = library.unifiedList(searchResults: [])
        #expect(list.map(\.id) == ["pub", "draft"])
    }
}

extension CloudKnowledgeMarketplaceListTests {
    @Test func unifiedListFilterSwitchesAllSubscribedAndOwned() {
        let library = CloudMarketplaceLibrary(
            subscribed: [
                .init(id: "sub", name: "已订阅", subscribed: true, ownerName: "Alice"),
            ],
            owned: [
                .init(id: "own", name: "我创建的", owned: true, publicationStatus: "published"),
            ]
        )
        let searchResults: [CloudMarketplaceKnowledgeBase] = [
            .init(id: "market", name: "市场"),
        ]

        #expect(library.unifiedList(searchResults: searchResults, filter: .all).map(\.id) == ["own", "sub", "market"])
        #expect(library.unifiedList(searchResults: searchResults, filter: .subscribed).map(\.id) == ["sub"])
        #expect(library.unifiedList(searchResults: searchResults, filter: .owned).map(\.id) == ["own"])
    }

    @Test func unifiedListOwnedFilterKeepsDraftAndPublishedAndMergedOwned() {
        let library = CloudMarketplaceLibrary(
            subscribed: [
                .init(id: "own", name: "我创建并订阅", subscribed: true, owned: true, publicationStatus: "published"),
            ],
            owned: [
                .init(id: "own", name: "我创建并订阅", owned: true, publicationStatus: "published"),
                .init(id: "draft", name: "草稿", owned: true, publicationStatus: nil),
            ]
        )
        let list = library.unifiedList(searchResults: [], filter: .owned)
        #expect(list.map(\.id) == ["own", "draft"])
        #expect(list.first?.subscribed == true)
    }
}
