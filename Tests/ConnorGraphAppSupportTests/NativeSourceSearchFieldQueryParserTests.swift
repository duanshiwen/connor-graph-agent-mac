import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search Field-aware Query Parser Tests")
struct NativeSourceSearchFieldQueryParserTests {
    @Test func parserExtractsKnownFieldsAndResidualText() {
        let parsed = NativeSearchFieldAwareQueryParser.parse("from:alice title:\"Q2 Plan\" launch")

        #expect(parsed.residualText == "launch")
        #expect(parsed.fieldConstraints[.sender] == ["alice"])
        #expect(parsed.fieldConstraints[.title] == ["q2 plan"])
    }

    @Test func parserParsesFeedLocationAndKind() {
        let parsed = NativeSearchFieldAwareQueryParser.parse("kind:rss feed:Swift location:杭州 search")

        #expect(parsed.residualText == "search")
        #expect(parsed.sourceKinds == [.rss])
        #expect(parsed.fieldConstraints[.feed] == ["swift"])
        #expect(parsed.fieldConstraints[.location] == ["杭州"])
    }

    @Test func parserParsesAfterBeforeSinceIntoTemporalFilter() throws {
        let parsed = NativeSearchFieldAwareQueryParser.parse("after:2026-06-01 before:2026-07-01 roadmap")

        let june1 = try date("2026-06-01T00:00:00Z")
        let july1 = try date("2026-07-01T00:00:00Z")
        let june10 = try date("2026-06-10T00:00:00Z")
        #expect(parsed.residualText == "roadmap")
        #expect(parsed.temporalFilter?.start == june1)
        #expect(parsed.temporalFilter?.end == july1)

        let since = NativeSearchFieldAwareQueryParser.parse("since:2026-06-10 update")
        #expect(since.temporalFilter?.start == june10)
    }

    @Test func unknownFieldRemainsSearchableText() {
        let parsed = NativeSearchFieldAwareQueryParser.parse("unknown:value actual query")

        #expect(parsed.residualText == "unknown:value actual query")
        #expect(parsed.fieldConstraints.isEmpty)
    }

    @Test func searchAppliesFieldConstraintsWithNaturalLanguageTokens() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "from-alice", title: "Roadmap", body: "launch plan", participants: ["Alice <alice@example.com>"]),
            document(id: "from-bob", title: "Roadmap", body: "launch plan", participants: ["Bob <bob@example.com>"])
        ])

        let query = NativeSearchFieldAwareQueryParser.parse("from:alice launch").makeQuery(limit: 10)
        let results = try await service.search(query)

        #expect(results.map(\.id) == ["from-alice"])
        #expect(results[0].diagnostics?.fieldConstraints["sender"] == ["alice"])
    }

    private func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private func document(id: String, title: String, body: String, participants: [String]) -> NativeSearchDocument {
        let time = Date(timeIntervalSince1970: 1_720_000_000)
        return NativeSearchDocument(
            id: id,
            sourceKind: .mail,
            externalID: id,
            title: title,
            summary: body,
            body: body,
            participants: participants,
            temporal: NativeSearchTemporalMetadata(primaryTime: time, primaryTimeKind: .sentAt, sentAt: time, indexedAt: time),
            contentHash: "hash-\(id)"
        )
    }
}
