import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Query Normalization Tests")
struct NativeSourceSearchQueryNormalizationTests {
    @Test func normalizerKeepsRawQueryAndSplitsStrongTokens() {
        let normalized = NativeSearchQueryNormalizer.normalize("the project update")

        #expect(normalized.rawText == "the project update")
        #expect(normalized.normalizedText == "the project update")
        #expect(normalized.strongTokenValues == ["project", "update"])
        #expect(normalized.softStopTokenValues == ["the"])
    }

    @Test func normalizerDoesNotDropShortTechnicalTokens() {
        let normalized = NativeSearchQueryNormalizer.normalize("AI RSS Q2 UI")

        #expect(normalized.strongTokenValues == ["ai", "rss", "q2", "ui"])
        #expect(normalized.softStopTokenValues.isEmpty)
    }

    @Test func normalizerTreatsChineseFunctionWordsAsSoftStopWords() {
        let normalized = NativeSearchQueryNormalizer.normalize("关于搜索的邮件")

        #expect(normalized.softStopTokenValues.contains("关于"))
        #expect(normalized.softStopTokenValues.contains("的"))
        #expect(normalized.strongTokenValues.contains("搜索"))
        #expect(normalized.strongTokenValues.contains("邮件"))
    }

    @Test func searchStillWorksWhenQueryContainsOnlySoftStopWords() async throws {
        let service = NativeSourceSearchService()
        let document = NativeSearchDocument(
            id: "mail-1",
            sourceKind: .mail,
            externalID: "mail-1",
            title: "The note",
            summary: "A small message",
            temporal: NativeSearchTemporalMetadata(sentAt: Date(timeIntervalSince1970: 1_000)),
            contentHash: "hash-1"
        )
        try await service.upsert([document])

        let results = try await service.search(NativeSearchQuery(text: "the"))

        #expect(results.map(\.id) == ["mail-1"])
        #expect(results.first?.diagnostics?.queryTokens == ["the"])
        #expect(results.first?.diagnostics?.softStopWords == ["the"])
    }

    @Test func cjkQueryGeneratesSearchableBigrams() {
        let normalized = NativeSearchQueryNormalizer.normalize("搜索性能优化")

        #expect(normalized.strongTokenValues.contains("搜索性能优化"))
        #expect(normalized.strongTokenValues.contains("搜索"))
        #expect(normalized.strongTokenValues.contains("性能"))
        #expect(normalized.strongTokenValues.contains("优化"))
    }

    @Test func chineseMailSearchMatchesBodyWithoutSpaces() async throws {
        let service = NativeSourceSearchService()
        let document = NativeSearchDocument(
            id: "mail-cn",
            sourceKind: .mail,
            externalID: "mail-cn",
            title: "中文邮件",
            summary: "搜索优化摘要",
            body: "这是关于搜索性能优化的邮件，里面没有任何空格。",
            temporal: NativeSearchTemporalMetadata(sentAt: Date(timeIntervalSince1970: 2_000)),
            contentHash: "hash-cn"
        )
        try await service.upsert([document])

        let results = try await service.search(NativeSearchQuery(text: "搜索性能", includeBodySnippets: true))

        #expect(results.map(\.id) == ["mail-cn"])
        #expect(results.first?.snippet.contains("搜索性能优化") == true)
    }

    @Test func mixedEnglishChineseQueryPreservesBothTokenFamilies() {
        let normalized = NativeSearchQueryNormalizer.normalize("RSS 搜索优化")

        #expect(normalized.strongTokenValues.contains("rss"))
        #expect(normalized.strongTokenValues.contains("搜索"))
        #expect(normalized.strongTokenValues.contains("优化"))
    }
}
