import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

struct GlobalSearchPreviewCoordinatorTests {
    @Test func previewResultsStreamsFastSourcesBeforeSlowSourcesSettle() async throws {
        let backend = DelayedNativeSourceSearchBackend(delays: [
            .mail: 20_000_000,
            .rss: 400_000_000,
            .calendar: 400_000_000,
            .browserHistory: 400_000_000
        ])
        let coordinator = GlobalSearchPreviewCoordinator(backend: backend, timeoutMilliseconds: 120)
        var iterator = coordinator.previewResults(query: "phoenix", limitsBySource: [.mail: 3, .rss: 3, .calendar: 3, .browserHistory: 3]).makeAsyncIterator()

        let first = try #require(await iterator.next())

        #expect(first.kind == .mail)
        #expect(first.results.map(\.id) == ["mail-result"])
        #expect(first.errorMessage == nil)
    }

    @Test func previewResultsSettleSlowSourcesAtPreviewTimeout() async throws {
        let backend = DelayedNativeSourceSearchBackend(delays: [
            .mail: 400_000_000,
            .rss: 400_000_000,
            .calendar: 400_000_000,
            .browserHistory: 400_000_000
        ])
        let coordinator = GlobalSearchPreviewCoordinator(backend: backend, timeoutMilliseconds: 80)
        var received: [GlobalSearchNativePreviewSectionResult] = []

        for await result in coordinator.previewResults(query: "phoenix", limitsBySource: [.mail: 3, .rss: 3, .calendar: 3, .browserHistory: 3]) {
            received.append(result)
        }

        #expect(received.count == NativeSearchSourceKind.allCases.count)
        #expect(received.allSatisfy { $0.results.isEmpty })
        #expect(received.allSatisfy { $0.errorMessage == nil })
    }

    @Test func previewResultsCancellationStopsOutstandingSearches() async throws {
        let backend = DelayedNativeSourceSearchBackend(delays: [
            .mail: 20_000_000,
            .rss: 400_000_000,
            .calendar: 400_000_000,
            .browserHistory: 400_000_000
        ])
        let coordinator = GlobalSearchPreviewCoordinator(backend: backend, timeoutMilliseconds: 1_000)
        var iterator: AsyncStream<GlobalSearchNativePreviewSectionResult>.Iterator? = coordinator
            .previewResults(query: "phoenix", limitsBySource: [.mail: 3, .rss: 3, .calendar: 3, .browserHistory: 3])
            .makeAsyncIterator()

        _ = await iterator?.next()
        iterator = nil
        try await Task.sleep(nanoseconds: 80_000_000)

        let cancelledKinds = await backend.cancelledKinds()
        #expect(!cancelledKinds.isEmpty)
    }
}

private actor DelayedNativeSourceSearchBackend: NativeSourceSearchBackend {
    var delays: [NativeSearchSourceKind: UInt64]
    private var cancelled: Set<NativeSearchSourceKind> = []

    init(delays: [NativeSearchSourceKind: UInt64]) {
        self.delays = delays
    }

    func cancelledKinds() -> Set<NativeSearchSourceKind> {
        cancelled
    }

    func upsert(_ documents: [NativeSearchDocument]) async throws {}
    func delete(documentIDs: [String]) async throws {}
    func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String?) async throws {}
    func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String?, documents: [NativeSearchDocument]) async throws {}

    func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult] {
        let kind = query.sourceKinds?.first ?? .mail
        if let delay = delays[kind] {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch is CancellationError {
                cancelled.insert(kind)
                throw CancellationError()
            }
        }
        return [Self.result(kind: kind)]
    }

    func health() async -> NativeSourceSearchHealthSnapshot {
        NativeSourceSearchHealthSnapshot()
    }

    private static func result(kind: NativeSearchSourceKind) -> NativeSearchResult {
        NativeSearchResult(
            id: "\(kind.rawValue)-result",
            sourceKind: kind,
            externalID: "\(kind.rawValue)-external",
            title: "\(kind.rawValue) result",
            snippet: "Preview result",
            score: 1,
            lexicalScore: 1,
            freshnessScore: 0,
            fieldScore: 0,
            temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 1_780_000_000), primaryTimeKind: .updatedAt),
            resultTimeLabel: "now"
        )
    }
}
