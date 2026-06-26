import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search FTS Query Builder Tests")
struct NativeSourceSearchFTSQueryBuilderTests {
    @Test func englishTermsBecomePrefixOrQuery() {
        let normalized = NativeSearchQueryNormalizer.normalize("project launch")
        let query = NativeSourceSearchFTSQueryBuilder.query(for: normalized)

        #expect(query.contains("project*"))
        #expect(query.contains("launch*"))
        #expect(query.contains(" OR "))
    }

    @Test func chineseTermsAreEscapedAndSearchable() {
        let normalized = NativeSearchQueryNormalizer.normalize("雅加达的豪华酒店推荐")
        let query = NativeSourceSearchFTSQueryBuilder.query(for: normalized)

        #expect(query.contains("雅加达") || query.contains("雅加"))
        #expect(!query.contains("'"))
        #expect(!query.contains("("))
        #expect(!query.contains(")"))
    }

    @Test func punctuationDoesNotBreakMatchSyntax() {
        let normalized = NativeSearchQueryNormalizer.normalize("hotel: jakarta (luxury) \"suite\"")
        let query = NativeSourceSearchFTSQueryBuilder.query(for: normalized)

        #expect(query.contains("hotel*"))
        #expect(query.contains("jakarta*"))
        #expect(query.contains("luxury*"))
        #expect(query.contains("suite*"))
        #expect(!query.contains(":"))
        #expect(!query.contains("("))
        #expect(!query.contains(")"))
    }

    @Test func chineseQueriesPreferSemanticTermsOverBroadFallbackGrams() {
        let normalized = NativeSearchQueryNormalizer.normalize("越南有什么好玩的嘛")
        let query = NativeSourceSearchFTSQueryBuilder.query(for: normalized)

        #expect(query.contains("越南"))
        #expect(query.contains("好玩"))
        #expect(!query.contains("南有"))
        #expect(!query.contains("什么"))
        #expect(!query.contains("么好"))
    }
}

