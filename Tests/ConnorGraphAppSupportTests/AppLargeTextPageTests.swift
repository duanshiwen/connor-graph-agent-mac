import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Bounded large text pages")
struct AppLargeTextPageTests {
    @Test func emptyAndOutOfRangePagesAreClamped() {
        let empty = AppLargeTextPage(source: "", index: 100)
        #expect(empty.text.isEmpty)
        #expect(empty.index == 0)
        #expect(empty.count == 1)
        let source = String(repeating: "a", count: 8_001)
        #expect(AppLargeTextPage(source: source, index: -1).index == 0)
        #expect(AppLargeTextPage(source: source, index: 100).text == "a")
    }

    @Test func multiMegabyteSingleParagraphIsLosslessAndBounded() {
        let source = String(repeating: "同步测试😀", count: 300_000)
        let count = AppLargeTextPage(source: source).count
        let pages = (0..<count).map { AppLargeTextPage(source: source, index: $0).text }
        #expect(pages.joined() == source)
        #expect(pages.allSatisfy { $0.utf16.count <= AppLargeTextPage.pageSize + 1 })
        #expect(!pages.contains { $0.contains("\u{FFFD}") })
    }

    @Test func emojiAcrossPageBoundaryIsNeitherSplitNorDuplicated() {
        let source = String(repeating: "a", count: 3_999) + "😀" + String(repeating: "b", count: 4_001)
        let pages = (0..<AppLargeTextPage(source: source).count).map {
            AppLargeTextPage(source: source, index: $0).text
        }
        #expect(pages.joined() == source)
        #expect(pages[0].utf16.count == 3_999)
        #expect(pages[1].hasPrefix("😀"))
    }

    @Test func pathologicalCombiningSequenceCannotBypassLayoutLimit() {
        let source = "a" + String(repeating: "\u{0301}", count: 100_000)
        #expect(source.count == 1)
        #expect(AppLargeTextPage(source: source).text.utf16.count == AppLargeTextPage.pageSize)
        let pages = (0..<AppLargeTextPage(source: source).count).map {
            AppLargeTextPage(source: source, index: $0).text
        }
        #expect(pages.joined() == source)
    }
}
