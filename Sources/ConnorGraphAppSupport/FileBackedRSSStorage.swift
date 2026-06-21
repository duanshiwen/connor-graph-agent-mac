import Foundation
import ConnorGraphCore

public actor FileBackedRSSSourceRepository: RSSSourceRepository {
    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageDirectory: URL, fileManager: FileManager = .default) {
        self.storageURL = storageDirectory.appendingPathComponent("sources.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storageURL = storagePaths.sourcesDirectory.appendingPathComponent("rss", isDirectory: true).appendingPathComponent("sources.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
    }

    public func listSources() async throws -> [RSSSource] {
        try loadSources().sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func source(id: RSSSourceID) async throws -> RSSSource? {
        try loadSources().first { $0.id == id }
    }

    public func saveSource(_ source: RSSSource) async throws {
        var sources = try loadSources()
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        try saveSources(sources)
    }

    public func deleteSource(id: RSSSourceID) async throws {
        let sources = try loadSources().filter { $0.id != id }
        try saveSources(sources)
    }

    private func loadSources() throws -> [RSSSource] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([RSSSource].self, from: data)
    }

    private func saveSources(_ sources: [RSSSource]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(sources)
        try writeAtomically(data, to: storageURL, fileManager: fileManager)
    }
}

public actor FileBackedRSSSourceCache: TimeAwareRSSSourceCache {
    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let searchService: NativeSourceSearchService?
    private var hasPrimedSearchIndex: Bool

    public init(storageDirectory: URL, fileManager: FileManager = .default, searchService: NativeSourceSearchService? = nil) {
        self.storageURL = storageDirectory.appendingPathComponent("items.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
        self.searchService = searchService
        self.hasPrimedSearchIndex = false
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default, searchService: NativeSourceSearchService? = nil) {
        self.storageURL = storagePaths.sourcesDirectory.appendingPathComponent("rss", isDirectory: true).appendingPathComponent("items.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
        self.searchService = searchService
        self.hasPrimedSearchIndex = false
    }

    public func listItems(sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        try filtered(sourceID: sourceID, includeHidden: includeHidden)
    }

    public func searchItems(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        try await searchItems(query: query, sourceID: sourceID, includeHidden: includeHidden, temporalFilter: nil, temporalSort: .relevanceThenTimeDesc, limit: Int.max)
    }

    public func searchItems(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [RSSItemSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        let items = try loadItems()
        if let searchService {
            try await primeSearchIndexIfNeeded(items: items)
            let results = try await searchService.search(NativeSearchQuery(text: query, sourceKinds: [.rss], sourceInstanceIDs: sourceID.map { Set([$0.rawValue]) }, temporalFilter: temporalFilter, temporalSort: temporalSort, limit: limit, includeHidden: includeHidden, rankingProfile: .recentFirst))
            let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id.rawValue, $0.summary) })
            return results.compactMap { byID[$0.externalID] }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = items.map(\.summary)
            .filter { sourceID == nil || $0.sourceID == sourceID }
            .filter { includeHidden || !$0.state.isHidden }
            .filter { item in
                guard let temporalFilter else { return true }
                return temporalFilter.contains(NativeSearchTemporalMetadata(primaryTime: item.publishedAt, primaryTimeKind: .publishedAt, publishedAt: item.publishedAt, fetchedAt: item.fetchedAt), sourceKind: .rss)
            }
            .filter { item in
                guard !trimmed.isEmpty else { return true }
                return item.title.localizedCaseInsensitiveContains(trimmed)
                    || item.snippet.localizedCaseInsensitiveContains(trimmed)
                    || (item.author?.localizedCaseInsensitiveContains(trimmed) == true)
            }
        let sorted = filteredItems.sorted { lhs, rhs in temporalSort == .timeAscThenRelevance || temporalSort == .relevanceThenTimeAsc ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt }
        return Array(sorted.prefix(limit))
    }

    public func item(id: RSSItemID) async throws -> RSSItemDetail? {
        try loadItems().first { $0.id == id }
    }

    public func upsertItems(_ newItems: [RSSItemDetail]) async throws -> (inserted: Int, duplicates: Int) {
        guard !newItems.isEmpty else { return (inserted: 0, duplicates: 0) }
        var items = try loadItems()
        var inserted = 0
        var duplicates = 0
        for newItem in newItems {
            if items.contains(where: { $0.id == newItem.id }) {
                duplicates += 1
            } else {
                items.append(newItem)
                inserted += 1
            }
        }
        try saveItems(items)
        let insertedItems = newItems.filter { candidate in items.contains { $0.id == candidate.id } }
        try await searchService?.upsert(insertedItems.map(NativeSourceSearchAdapters.rssDocument(from:)))
        return (inserted, duplicates)
    }

    public func updateState(itemIDs: [RSSItemID], transform: @Sendable (RSSItemState) -> RSSItemState) async throws {
        guard !itemIDs.isEmpty else { return }
        let targetIDs = Set(itemIDs)
        var items = try loadItems()
        var didChange = false
        for index in items.indices where targetIDs.contains(items[index].id) {
            items[index].summary.state = transform(items[index].summary.state)
            didChange = true
        }
        if didChange {
            try saveItems(items)
            let changed = items.filter { targetIDs.contains($0.id) }
            try await searchService?.upsert(changed.map(NativeSourceSearchAdapters.rssDocument(from:)))
        }
    }

    public func deleteItems(sourceID: RSSSourceID) async throws {
        let items = try loadItems()
        let filteredItems = items.filter { $0.summary.sourceID != sourceID }
        if filteredItems.count != items.count {
            try saveItems(filteredItems)
            try await searchService?.deleteBySource(kind: .rss, sourceInstanceID: sourceID.rawValue)
        }
    }

    private func primeSearchIndexIfNeeded(items: [RSSItemDetail]) async throws {
        guard let searchService, !hasPrimedSearchIndex else { return }
        try await searchService.rebuildSource(kind: .rss, documents: items.map(NativeSourceSearchAdapters.rssDocument(from:)))
        hasPrimedSearchIndex = true
    }

    private func filtered(sourceID: RSSSourceID?, includeHidden: Bool) throws -> [RSSItemSummary] {
        try loadItems().map(\.summary)
            .filter { sourceID == nil || $0.sourceID == sourceID }
            .filter { includeHidden || !$0.state.isHidden }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func loadItems() throws -> [RSSItemDetail] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([RSSItemDetail].self, from: data)
    }

    private func saveItems(_ items: [RSSItemDetail]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(items)
        try writeAtomically(data, to: storageURL, fileManager: fileManager)
    }
}

private func rssStorageJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func rssStorageJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func writeAtomically(_ data: Data, to url: URL, fileManager: FileManager) throws {
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
    try data.write(to: temporaryURL, options: [.atomic])
    if fileManager.fileExists(atPath: url.path) {
        _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
    } else {
        try fileManager.moveItem(at: temporaryURL, to: url)
    }
}
