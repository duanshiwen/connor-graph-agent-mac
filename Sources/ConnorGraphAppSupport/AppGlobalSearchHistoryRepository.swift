import Foundation

public struct GlobalSearchHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var query: String
    public var normalizedQuery: String
    public var searchedAt: Date
    public var useCount: Int

    public init(
        id: String,
        query: String,
        normalizedQuery: String,
        searchedAt: Date,
        useCount: Int
    ) {
        self.id = id
        self.query = query
        self.normalizedQuery = normalizedQuery
        self.searchedAt = searchedAt
        self.useCount = useCount
    }
}

public struct AppGlobalSearchHistoryRepository: Sendable {
    public var historyURL: URL
    public var maxStoredEntries: Int

    public init(historyURL: URL, maxStoredEntries: Int = 20) {
        self.historyURL = historyURL
        self.maxStoredEntries = max(1, maxStoredEntries)
    }

    public func load() throws -> [GlobalSearchHistoryEntry] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        let data = try Data(contentsOf: historyURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GlobalSearchHistoryEntry].self, from: data)
            .sorted { lhs, rhs in
                if lhs.searchedAt != rhs.searchedAt { return lhs.searchedAt > rhs.searchedAt }
                return lhs.query.localizedCaseInsensitiveCompare(rhs.query) == .orderedAscending
            }
            .prefix(maxStoredEntries)
            .map { $0 }
    }

    @discardableResult
    public func record(query: String, now: Date = Date()) throws -> [GlobalSearchHistoryEntry] {
        let displayQuery = Self.displayQuery(for: query)
        let normalizedQuery = Self.normalizedQuery(for: displayQuery)
        guard !normalizedQuery.isEmpty else { return try load() }

        var entries = try load()
        if let existingIndex = entries.firstIndex(where: { $0.normalizedQuery == normalizedQuery }) {
            var entry = entries.remove(at: existingIndex)
            entry.query = displayQuery
            entry.normalizedQuery = normalizedQuery
            entry.searchedAt = now
            entry.useCount += 1
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                GlobalSearchHistoryEntry(
                    id: normalizedQuery,
                    query: displayQuery,
                    normalizedQuery: normalizedQuery,
                    searchedAt: now,
                    useCount: 1
                ),
                at: 0
            )
        }

        entries = Array(entries.prefix(maxStoredEntries))
        try save(entries)
        return entries
    }

    public func clear() throws {
        try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try save([])
    }

    public static func displayQuery(for query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func normalizedQuery(for query: String) -> String {
        displayQuery(for: query).lowercased()
    }

    private func save(_ entries: [GlobalSearchHistoryEntry]) throws {
        try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: historyURL, options: .atomic)
    }
}
