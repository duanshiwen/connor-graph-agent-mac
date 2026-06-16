import Foundation

/// Persists browser bookmarks as a JSONL file at `browser/bookmarks.jsonl`.
/// Global across all sessions — bookmarks are a browser-level concern, not session-scoped.
public final class BrowserBookmarkStore: @unchecked Sendable {
    private let bookmarksURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.connor.browser-bookmark-store", qos: .utility)

    public init(bookmarksURL: URL, fileManager: FileManager = .default) {
        self.bookmarksURL = bookmarksURL
        self.fileManager = fileManager
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Load all bookmarks sorted by `createdAt` ascending.
    public func loadBookmarks() -> [BrowserBookmarkRecord] {
        queue.sync { loadBookmarksUnsafe() }
    }

    /// Insert or update a bookmark by URL. Existing records keep their original ID and createdAt.
    public func upsertBookmark(_ bookmark: BrowserBookmarkRecord) {
        queue.sync {
            var records = loadBookmarksUnsafe()
            if let index = records.firstIndex(where: { $0.url == bookmark.url }) {
                let existing = records[index]
                records[index] = BrowserBookmarkRecord(
                    id: existing.id,
                    url: bookmark.url,
                    title: bookmark.title,
                    groupName: bookmark.groupName,
                    createdAt: existing.createdAt,
                    updatedAt: bookmark.updatedAt
                )
            } else {
                records.append(bookmark)
            }
            saveBookmarksUnsafe(records)
        }
    }

    public func searchBookmarks(query: String) -> [BrowserBookmarkRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return loadBookmarks() }
        return queue.sync {
            loadBookmarksUnsafe().filter { bookmark in
                bookmark.url.lowercased().contains(trimmed)
                    || bookmark.title.lowercased().contains(trimmed)
                    || bookmark.groupName.lowercased().contains(trimmed)
            }
        }
    }

    public func bookmarks(groupName: String?) -> [BrowserBookmarkRecord] {
        let normalized = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return loadBookmarks() }
        return queue.sync { loadBookmarksUnsafe().filter { $0.groupName == normalized } }
    }

    public func groups() -> [String] {
        queue.sync {
            let names = Set(loadBookmarksUnsafe().map { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BrowserBookmarkRecord.defaultGroupName : $0.groupName })
            return names.sorted { lhs, rhs in
                if lhs == BrowserBookmarkRecord.defaultGroupName { return true }
                if rhs == BrowserBookmarkRecord.defaultGroupName { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    public func deleteBookmark(id: UUID) {
        queue.sync {
            var records = loadBookmarksUnsafe()
            records.removeAll { $0.id == id }
            saveBookmarksUnsafe(records)
        }
    }

    public func deleteBookmark(url: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        queue.sync {
            var records = loadBookmarksUnsafe()
            records.removeAll { $0.url == trimmedURL }
            saveBookmarksUnsafe(records)
        }
    }

    public func clearBookmarks() {
        queue.sync {
            guard fileManager.fileExists(atPath: bookmarksURL.path) else { return }
            try? fileManager.removeItem(at: bookmarksURL)
        }
    }

    // MARK: - Private

    private func loadBookmarksUnsafe() -> [BrowserBookmarkRecord] {
        guard fileManager.fileExists(atPath: bookmarksURL.path) else { return [] }
        guard let data = try? Data(contentsOf: bookmarksURL) else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [BrowserBookmarkRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let record = try? decoder.decode(BrowserBookmarkRecord.self, from: lineData)
            else { continue }
            records.append(record)
        }
        return records.sorted { $0.createdAt < $1.createdAt }
    }

    private func saveBookmarksUnsafe(_ records: [BrowserBookmarkRecord]) {
        let dir = bookmarksURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !records.isEmpty else {
            try? fileManager.removeItem(at: bookmarksURL)
            return
        }
        let lines = records.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(to: bookmarksURL, atomically: true, encoding: .utf8)
    }
}
