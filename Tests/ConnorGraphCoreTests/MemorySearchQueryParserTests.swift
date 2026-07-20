import Testing
import ConnorGraphCore

@Suite("Memory Search Query Parser Tests")
struct MemorySearchQueryParserTests {
    @Test func preservesWhitespaceQueryAsPhraseAndBroadTerms() {
        let plan = MemorySearchQueryParser.parse("  Annie Friend  ")

        #expect(plan.normalizedText == "Annie Friend")
        #expect(plan.phrases == ["Annie Friend"])
        #expect(plan.terms == ["Annie", "Friend"])
        #expect(plan.retrievalTerms == ["Annie Friend", "Annie", "Friend"])
    }

    @Test(arguments: [",", "，", ";", "；", "、", "|", "｜", "\n", "\t"])
    func acceptsCommonLLMSeparators(_ separator: String) {
        let plan = MemorySearchQueryParser.parse("Annie\(separator)Friend")

        #expect(plan.terms == ["Annie", "Friend"])
    }

    @Test func quotedTextRemainsASingleSearchTerm() {
        let plan = MemorySearchQueryParser.parse("\"Annie Friend\"；AI 产品经理")

        #expect(plan.phrases == ["Annie Friend"])
        #expect(plan.terms == ["Annie Friend", "AI", "产品经理"])
    }

    @Test func normalizesWidthAndDeduplicatesCaseInsensitively() {
        let plan = MemorySearchQueryParser.parse("Ａｎｎｉｅ;annie;ANNIE")

        #expect(plan.terms == ["Annie"])
    }
}
