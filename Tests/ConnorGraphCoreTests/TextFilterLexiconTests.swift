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
}
