import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Indexed Text Builder Tests")
struct NativeSourceSearchIndexedTextBuilderTests {
    @Test func chineseIndexedTextContainsOriginalSemanticTokensAndNgrams() {
        let document = NativeSearchDocument(
            id: "rss-cn",
            sourceKind: .rss,
            externalID: "rss-cn",
            title: "雅加达的豪华酒店推荐",
            summary: "适合商务舱旅客的酒店清单",
            body: "包含市中心、套房、早餐和机场交通。",
            contentHash: "hash"
        )

        let text = NativeSourceSearchIndexedTextBuilder.searchableText(for: document)

        #expect(text.contains("雅加达的豪华酒店推荐"))
        #expect(text.contains("雅加达") || text.contains("雅加"))
        #expect(text.contains("豪华") || text.contains("豪华酒"))
        #expect(text.contains("酒店") || text.contains("酒店推"))
    }

    @Test func indexedTextIncludesMetadataParticipantsAndLocation() {
        let document = NativeSearchDocument(
            id: "mail-1",
            sourceKind: .mail,
            externalID: "mail-1",
            title: "Launch",
            summary: "Planning",
            body: "Project body",
            participants: ["Ada Lovelace"],
            location: "Hangzhou",
            metadata: ["tag": "priority"],
            contentHash: "hash"
        )

        let text = NativeSourceSearchIndexedTextBuilder.searchableText(for: document)

        #expect(text.contains("launch"))
        #expect(text.contains("ada lovelace"))
        #expect(text.contains("hangzhou"))
        #expect(text.contains("priority"))
    }
}
