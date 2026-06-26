import Testing
@testable import ConnorGraphCore

@Suite("Text Filter Lexicon Tests")
struct TextFilterLexiconTests {
    @Test func defaultLexiconContainsCoreChineseAndEnglishEntries() {
        let lexicon = TextFilterLexicon.default

        #expect(lexicon.entry(for: "的")?.categories.contains(.functionWord) == true)
        #expect(lexicon.entry(for: "一个")?.categories.contains(.quantifier) == true)
        #expect(lexicon.entry(for: "需要")?.categories.contains(.modal) == true)
        #expect(lexicon.entry(for: "多少")?.categories.contains(.questionWord) == true)
        #expect(lexicon.entry(for: "星期")?.categories.contains(.temporalFiller) == true)
        #expect(lexicon.entry(for: "the")?.categories.contains(.englishStopWord) == true)
    }

    @Test func temporalWordsAreSoftDemotedNotDroppedFromQuery() {
        let lexicon = TextFilterLexicon.default

        #expect(lexicon.action(for: "星期", context: .searchQuery) == .softDemote)
        #expect(lexicon.action(for: "星期", context: .indexing) == .keep)
        #expect(lexicon.entry(for: "星期")?.preserveInPhrase == true)
    }

    @Test func lowValueQuestionAndQuantifierWordsDropFromDisplayOnly() {
        let lexicon = TextFilterLexicon.default

        #expect(lexicon.action(for: "一个", context: .searchDisplay) == .dropForDisplay)
        #expect(lexicon.action(for: "多少", context: .searchDisplay) == .dropForDisplay)
        #expect(lexicon.action(for: "需要", context: .searchDisplay) == .dropForDisplay)
        #expect(lexicon.action(for: "一个", context: .searchQuery) == .softDemote)
    }

    @Test func unknownTermsAreKeptWithFullWeight() {
        let lexicon = TextFilterLexicon.default

        #expect(lexicon.entry(for: "雅加达") == nil)
        #expect(lexicon.action(for: "雅加达", context: .searchQuery) == .keep)
        #expect(lexicon.weightMultiplier(for: "雅加达", context: .searchQuery) == 1)
    }

    @Test func expandedChineseLexiconCoversCommonFunctionQuantifierTemporalAndQuestionWords() {
        let lexicon = TextFilterLexicon.default

        for term in ["请", "帮忙", "大概", "还是", "或者", "之后", "之前", "每个", "大约", "左右", "附近", "最近", "周五", "礼拜", "多少钱", "多长时间"] {
            #expect(lexicon.contains(term), "Expected default lexicon to contain \(term)")
        }

        #expect(lexicon.entry(for: "周五")?.categories.contains(.temporalFiller) == true)
        #expect(lexicon.entry(for: "多少钱")?.categories.contains(.questionWord) == true)
        #expect(lexicon.action(for: "周五", context: .indexing) == .keep)
        #expect(lexicon.action(for: "多少钱", context: .searchDisplay) == .dropForDisplay)
    }
}

