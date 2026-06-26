import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Global Search Performance Tests")
struct GlobalSearchPerformanceTests {
    @Test func sqliteFTSSearchUsesMatchForLargeCorpus() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        var documents: [NativeSearchDocument] = []
        for index in 0..<2_000 {
            documents.append(NativeSearchDocument(
                id: "doc-\(index)",
                sourceKind: index.isMultiple(of: 2) ? .rss : .browserHistory,
                externalID: "doc-\(index)",
                title: "Noise document \(index)",
                summary: "ordinary unrelated content",
                body: "coffee travel note weather city \(index)",
                temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: Double(index)), primaryTimeKind: .updatedAt, updatedAt: Date(timeIntervalSince1970: Double(index))),
                contentHash: "doc-\(index)"
            ))
        }
        documents.append(NativeSearchDocument(
            id: "target-mail",
            sourceKind: .mail,
            externalID: "target-mail",
            title: "Project Phoenix launch",
            summary: "The project phoenix launch decision is ready.",
            contentHash: "target-mail"
        ))
        try await backend.upsert(documents)

        let started = Date()
        let grouped = try await backend.searchGrouped(
            NativeSearchQuery(text: "project phoenix launch", sourceKinds: [.mail, .rss, .browserHistory], limit: 9),
            limitsBySource: [.mail: 3, .rss: 3, .browserHistory: 3]
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(grouped[.mail]?.first?.id == "target-mail")
        #expect(grouped[.mail]?.first?.diagnostics?.rankReason.contains("match=true") == true)
        #expect(elapsed < 1.0)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlobalSearchPerformanceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("search.sqlite")
    }
}
