import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

private struct RSSStaticFetcher: RSSFetchAdapter {
    var result: Result<Data, Error>

    func fetch(url: URL, timeoutSeconds: Int) async throws -> Data {
        try result.get()
    }
}

private enum RSSFeatureTestError: Error, LocalizedError {
    case fetchFailed
    case stateMutationFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed: "fixture fetch failed"
        case .stateMutationFailed: "fixture state mutation failed"
        }
    }
}

private actor RSSFailingStateCache: RSSSourceCache {
    private let base: InMemoryRSSSourceCache

    init(items: [RSSItemDetail]) {
        base = InMemoryRSSSourceCache(items: items)
    }

    func listItems(sourceID: RSSSourceID?, includeHidden: Bool) async throws -> [RSSItemSummary] {
        try await base.listItems(sourceID: sourceID, includeHidden: includeHidden)
    }

    func searchItems(query: String, sourceID: RSSSourceID?, includeHidden: Bool) async throws -> [RSSItemSummary] {
        try await base.searchItems(query: query, sourceID: sourceID, includeHidden: includeHidden)
    }

    func item(id: RSSItemID) async throws -> RSSItemDetail? {
        try await base.item(id: id)
    }

    func upsertItems(_ items: [RSSItemDetail]) async throws -> (inserted: Int, duplicates: Int) {
        try await base.upsertItems(items)
    }

    func updateState(itemIDs: [RSSItemID], transform: @Sendable (RSSItemState) -> RSSItemState) async throws {
        throw RSSFeatureTestError.stateMutationFailed
    }

    func deleteItems(sourceID: RSSSourceID) async throws {
        try await base.deleteItems(sourceID: sourceID)
    }
}

private let rssFixtureXML = Data("""
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Fixture Feed</title><link>https://example.com</link>
<item><guid>article-1</guid><title>Fixture Article</title><link>https://example.com/article</link><description>Fixture body</description></item>
</channel></rss>
""".utf8)

private func makeRSSFixture() -> (RSSSource, RSSItemDetail) {
    let sourceID = RSSSourceID(rawValue: "source-1")
    let source = RSSSource(
        id: sourceID,
        feedURL: URL(string: "https://example.com/feed.xml")!,
        displayName: "Fixture"
    )
    let item = RSSItemDetail(summary: RSSItemSummary(
        id: RSSItemID(rawValue: "item-1"),
        sourceID: sourceID,
        title: "Fixture Article",
        link: URL(string: "https://example.com/article"),
        snippet: "Fixture body",
        state: RSSItemState(isRead: false)
    ))
    return (source, item)
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !predicate(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
@Test func rssFeatureReloadBuildsPresentationAndPreservesOrFallsBackSelection() async {
    let (source, item) = makeRSSFixture()
    let repository = InMemoryRSSSourceRepository(sources: [source])
    let cache = InMemoryRSSSourceCache(items: [item])
    let model = RSSFeatureModel(runtime: RSSRuntime(repository: repository, cache: cache))

    await model.reload()
    #expect(model.presentation.sources == [source])
    #expect(model.presentation.items == [item.summary])
    #expect(model.selectedSourceID == source.id)
    #expect(model.selectedItemID == item.id)

    model.selectedSourceID = source.id
    model.selectedItemID = item.id
    await model.reload()
    #expect(model.selectedSourceID == source.id)
    #expect(model.selectedItemID == item.id)

    try? await repository.deleteSource(id: source.id)
    try? await cache.deleteItems(sourceID: source.id)
    await model.reload()
    #expect(model.selectedSourceID == nil)
    #expect(model.selectedItemID == nil)
}

@MainActor
@Test func rssFeatureCachesVisibleItemsAcrossSearchAndPresentationChanges() {
    let (source, item) = makeRSSFixture()
    let second = RSSItemSummary(
        id: RSSItemID(rawValue: "item-2"),
        sourceID: source.id,
        title: "Swift Performance",
        snippet: "Navigation profiling"
    )
    let model = RSSFeatureModel(runtime: RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(items: [])
    ))

    model.presentation = NativeRSSBrowserPresentation(sources: [source], items: [item.summary, second])
    #expect(model.visibleItems.map(\.id) == [item.id, second.id])

    model.searchQuery = "performance"
    #expect(model.visibleItems.map(\.id) == [second.id])

    model.presentation = NativeRSSBrowserPresentation(sources: [source], items: [item.summary])
    #expect(model.visibleItems.isEmpty)
}

@MainActor
@Test func rssFeatureLoadsEveryItemThroughStablePages() async throws {
    let (source, _) = makeRSSFixture()
    let baseDate = try #require(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    let items = (0..<130).map { index in
        RSSItemDetail(summary: RSSItemSummary(
            id: RSSItemID(rawValue: String(format: "item-%03d", index)),
            sourceID: source.id,
            title: index.isMultiple(of: 2) ? "Even article \(index)" : "Odd article \(index)",
            publishedAt: baseDate.addingTimeInterval(TimeInterval(-index)),
            snippet: "Body \(index)"
        ))
    }
    let model = RSSFeatureModel(runtime: RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(items: items)
    ))

    await model.reload()
    #expect(model.visibleWindowItems.count == 50)

    model.loadMoreVisibleItemsIfNeeded(currentItemID: items[10].id)
    await model.waitForPendingOperations()
    #expect(model.visibleWindowItems.count == 50)

    let firstPageEnd = try #require(model.visibleWindowItems.last?.id)
    model.loadMoreVisibleItemsIfNeeded(currentItemID: firstPageEnd)
    model.loadMoreVisibleItemsIfNeeded(currentItemID: firstPageEnd)
    await model.waitForPendingOperations()
    #expect(model.visibleWindowItems.count == 100)

    model.loadMoreVisibleItemsIfNeeded(currentItemID: try #require(model.visibleWindowItems.last?.id))
    await model.waitForPendingOperations()
    #expect(model.visibleWindowItems.count == 130)
    #expect(Set(model.visibleWindowItems.map(\.id)).count == 130)

    model.searchQuery = "Even article"
    await model.waitForPendingOperations()
    #expect(model.visibleWindowItems.count == 50)
    model.loadMoreVisibleItemsIfNeeded(currentItemID: try #require(model.visibleWindowItems.last?.id))
    await model.waitForPendingOperations()
    #expect(model.visibleWindowItems.count == 65)
    #expect(Set(model.visibleWindowItems.map(\.id)).count == 65)
}

@MainActor
@Test func rssFeatureSelectOptimisticallyMarksReadAndPersists() async throws {
    let (source, item) = makeRSSFixture()
    let cache = InMemoryRSSSourceCache(items: [item])
    let model = RSSFeatureModel(runtime: RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: cache
    ))
    await model.reload()

    model.selectItem(item.summary)

    #expect(model.selectedSourceID == source.id)
    #expect(model.selectedItemID == item.id)
    #expect(model.presentation.item(id: item.id)?.state.isRead == true)
    await model.waitForPendingOperations()
    let persisted = try await cache.item(id: item.id)
    #expect(persisted?.summary.state.isRead == true)
}

@MainActor
@Test func rssFeatureReadFailureRollsBackAndReportsDomainError() async {
    let (source, item) = makeRSSFixture()
    let model = RSSFeatureModel(runtime: RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: RSSFailingStateCache(items: [item])
    ))
    await model.reload()

    model.selectItem(item.summary)
    #expect(model.presentation.item(id: item.id)?.state.isRead == true)
    await model.waitForPendingOperations()

    #expect(model.presentation.item(id: item.id)?.state.isRead == false)
    #expect(model.errorMessage?.contains("stateMutationFailed") == true)
}

@MainActor
@Test func rssFeatureAddKeepsSourceWhenInitialSyncFailsAndEmitsChange() async throws {
    let repository = InMemoryRSSSourceRepository()
    let runtime = RSSRuntime(
        repository: repository,
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .failure(RSSFeatureTestError.fetchFailed))
    )
    let model = RSSFeatureModel(runtime: runtime)
    var sourceChangeScopes: [RSSFeatureModel.SourceSetChangeScope] = []
    model.sourceSetChanged = { sourceChangeScopes.append($0) }

    try await model.addSourceAndSync(
        feedURL: URL(string: "https://example.com/feed.xml")!,
        displayName: "Fixture"
    )

    #expect(try await repository.listSources().count == 1)
    #expect(model.presentation.sources.count == 1)
    #expect(model.errorMessage == "RSS 订阅源已添加，但首次抓取失败：fixture fetch failed")
    #expect(sourceChangeScopes == [.rssOnly])
}

@MainActor
@Test func rssFeatureUpdateAndDeleteEmitSourceChangeOnlyAfterMutation() async throws {
    let (source, item) = makeRSSFixture()
    let repository = InMemoryRSSSourceRepository(sources: [source])
    let cache = InMemoryRSSSourceCache(items: [item])
    let model = RSSFeatureModel(runtime: RSSRuntime(repository: repository, cache: cache))
    var sourceChangeScopes: [RSSFeatureModel.SourceSetChangeScope] = []
    model.sourceSetChanged = { sourceChangeScopes.append($0) }
    await model.reload()

    try await model.updateSource(
        sourceID: source.id,
        feedURL: source.feedURL,
        displayName: "Renamed"
    )
    #expect(sourceChangeScopes == [.rssOnly])
    #expect(model.presentation.sources.first?.displayName == "Renamed")

    let updated = try #require(model.presentation.sources.first)
    model.pendingSourceDeletion = updated
    model.deleteSource(updated)
    await waitUntil { model.presentation.sources.isEmpty }
    #expect(sourceChangeScopes == [.rssOnly, .allSources])
    #expect(model.pendingSourceDeletion == nil)
    #expect(model.selectedSourceID == nil)
    #expect(model.selectedItemID == nil)
}

@MainActor
@Test func rssFeatureFollowValidatesURLMarksReadAndSendsValueRequest() async {
    let (source, item) = makeRSSFixture()
    let model = RSSFeatureModel(runtime: RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(items: [item])
    ))
    var requests: [RSSFollowRequest] = []
    model.onFollowRequest = { requests.append($0) }
    await model.reload()

    var missingLinkItem = item.summary
    missingLinkItem.link = nil
    model.followItem(missingLinkItem)
    #expect(requests.isEmpty)
    #expect(model.errorMessage == "这篇 RSS 文章没有可打开的原文链接。")

    model.followItem(item.summary)

    #expect(requests == [RSSFollowRequest(
        itemID: item.id.rawValue,
        title: item.summary.title,
        url: item.summary.link!
    )])
    #expect(model.presentation.item(id: item.id)?.state.isRead == true)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func rssFeatureScheduledRefreshPreservesExistingResultMessages() async throws {
    let source = RSSSource(
        id: RSSSourceID(rawValue: "scheduled-source"),
        feedURL: URL(string: "https://example.com/feed.xml")!,
        displayName: "Fixture"
    )
    let runtime = RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .success(rssFixtureXML))
    )
    let model = RSSFeatureModel(runtime: runtime)

    let single = try await model.refreshForScheduledTask(
        sourceInstanceID: source.id.rawValue,
        runID: "run-1"
    )
    #expect(single == "RSS refreshed source scheduled-source; inserted 1, duplicates 0")

    let all = try await model.refreshForScheduledTask(sourceInstanceID: nil, runID: "run-2")
    #expect(all == "RSS refreshed 1 sources; inserted 0, duplicates 1")
    #expect(model.presentation.items.count == 1)
}

@Test func rssRuntimeErrorClassifiesPermanentHTTPFailures() {
    #expect(RSSRuntimeError.unsupportedFeed("HTTP 404").isPermanentHTTPFailure == true)
    #expect(RSSRuntimeError.unsupportedFeed("HTTP 403").isPermanentHTTPFailure == true)
    #expect(RSSRuntimeError.unsupportedFeed("HTTP 410").isPermanentHTTPFailure == true)
    #expect(RSSRuntimeError.unsupportedFeed("HTTP 500").isPermanentHTTPFailure == false)
    #expect(RSSRuntimeError.unsupportedFeed("not json feed").isPermanentHTTPFailure == false)
}

@MainActor
@Test func rssFeatureScheduledRefreshAutoRemovesPermanentHTTPFailureSource() async throws {
    let dead = RSSSource(
        id: RSSSourceID(rawValue: "dead-404"),
        feedURL: URL(string: "https://dead.example.com/feed.xml")!,
        displayName: "Dead 404"
    )
    let repository = InMemoryRSSSourceRepository(sources: [dead])
    let runtime = RSSRuntime(
        repository: repository,
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .failure(RSSRuntimeError.unsupportedFeed("HTTP 404")))
    )
    let model = RSSFeatureModel(runtime: runtime)

    await #expect(throws: RSSRuntimeError.self) {
        try await model.refreshForScheduledTask(sourceInstanceID: dead.id.rawValue, runID: "run-1")
    }
    let remaining = try await repository.source(id: dead.id)
    #expect(remaining == nil)
}

@MainActor
@Test func rssFeatureRefreshAllRemovesAllPermanentFailureSources() async throws {
    let dead = RSSSource(
        id: RSSSourceID(rawValue: "dead-403"),
        feedURL: URL(string: "https://dead.example.com/feed.xml")!,
        displayName: "Dead 403"
    )
    let healthy = RSSSource(
        id: RSSSourceID(rawValue: "healthy"),
        feedURL: URL(string: "https://ok.example.com/feed.xml")!,
        displayName: "Healthy"
    )
    let repository = InMemoryRSSSourceRepository(sources: [dead, healthy])
    let runtime = RSSRuntime(
        repository: repository,
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .failure(RSSRuntimeError.unsupportedFeed("HTTP 403")))
    )
    let model = RSSFeatureModel(runtime: runtime)
    // 全部刷新时两个源都会失败（fetch 按 URL 区分：dead 403、healthy 也 403，这里验证
    // 404/403 自动删除；健康源场景由下面的 URL 分流 fetcher 覆盖）
    _ = model
    let summary = try await model.refreshForScheduledTask(sourceInstanceID: nil, runID: "run-2")
    #expect(summary.contains("removed 2 dead source(s)"))
    #expect(try await repository.source(id: dead.id) == nil)
    #expect(try await repository.source(id: healthy.id) == nil)
}

@MainActor
@Test func rssFeatureRefreshAllSkipsOnlyDeadSourcesAndKeepsHealthy() async throws {
    struct URLSwitchingRSSFetcher: RSSFetchAdapter {
        let failingURL: String
        let successData: Data
        func fetch(url: URL, timeoutSeconds: Int) async throws -> Data {
            if url.absoluteString == failingURL {
                throw RSSRuntimeError.unsupportedFeed("HTTP 404")
            }
            return successData
        }
    }
    let dead = RSSSource(
        id: RSSSourceID(rawValue: "dead-404"),
        feedURL: URL(string: "https://dead.example.com/feed.xml")!,
        displayName: "Dead 404"
    )
    let healthy = RSSSource(
        id: RSSSourceID(rawValue: "healthy"),
        feedURL: URL(string: "https://ok.example.com/feed.xml")!,
        displayName: "Healthy"
    )
    let repository = InMemoryRSSSourceRepository(sources: [dead, healthy])
    let runtime = RSSRuntime(
        repository: repository,
        cache: InMemoryRSSSourceCache(),
        fetcher: URLSwitchingRSSFetcher(failingURL: dead.feedURL.absoluteString, successData: rssFixtureXML)
    )
    let model = RSSFeatureModel(runtime: runtime)

    let summary = try await model.refreshForScheduledTask(sourceInstanceID: nil, runID: "run-3")
    #expect(summary.contains("removed 1 dead source(s)"))
    #expect(try await repository.source(id: dead.id) == nil)
    #expect(try await repository.source(id: healthy.id) != nil)
}
@MainActor
@Test func rssFeatureRefreshAllNowRefreshesEverySource() async throws {
    let (source, _) = makeRSSFixture()
    let runtime = RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .success(rssFixtureXML))
    )
    let model = RSSFeatureModel(runtime: runtime)

    model.refreshAllNow()
    await model.waitForPendingOperations()

    #expect(!model.isRefreshingAll)
    #expect(model.errorMessage == nil)
    #expect(model.refreshSummary == "RSS refreshed 1 sources; inserted 1, duplicates 0")
    #expect(model.presentation.items.count == 1)
}

@MainActor
@Test func rssFeatureSyncStatusBannerIsDismissibleAndResetsOnNextRefresh() async throws {
    let (source, _) = makeRSSFixture()
    let runtime = RSSRuntime(
        repository: InMemoryRSSSourceRepository(sources: [source]),
        cache: InMemoryRSSSourceCache(),
        fetcher: RSSStaticFetcher(result: .success(rssFixtureXML))
    )
    let model = RSSFeatureModel(runtime: runtime)

    model.refreshAllNow()
    #expect(model.showsSyncStatusBanner)
    model.dismissSyncStatusBanner()
    #expect(!model.showsSyncStatusBanner)

    await model.waitForPendingOperations()

    // 下一次新同步开始时自动恢复显示。
    model.refreshAllNow()
    #expect(model.showsSyncStatusBanner)
    await model.waitForPendingOperations()
    #expect(!model.isRefreshingAll)
}
