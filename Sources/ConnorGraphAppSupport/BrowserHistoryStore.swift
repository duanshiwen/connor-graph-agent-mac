import Foundation

/// Persists browser history as a JSONL file at `browser/history.jsonl`.
/// Global across all sessions — history is a browser-level concern, not session-scoped.
public final class BrowserHistoryStore: @unchecked Sendable {
    public static let maxRecordCount: Int = 10_000
    public static let deduplicationWindowSeconds: TimeInterval = 5

    private let historyURL: URL
    private let fileManager: FileManager
    private let recordLimit: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.connor.browser-history-store", qos: .utility)
    private var cachedRecordCount: Int?
    private var cachedLastRecord: BrowserHistoryRecord?

    public init(historyURL: URL, fileManager: FileManager = .default, maxRecordCount: Int = BrowserHistoryStore.maxRecordCount) {
        self.historyURL = historyURL
        self.fileManager = fileManager
        self.recordLimit = maxRecordCount
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Append a record. Deduplicates against the most recent entry with the same URL
    /// within `deduplicationWindowSeconds`. Also enforces `maxRecordCount`.
    ///
    /// This is intentionally optimized for the browser hot path: normal writes append one
    /// JSON line instead of reading and rewriting the full history file on every navigation.
    @discardableResult
    public func appendRecord(_ record: BrowserHistoryRecord) -> BrowserHistoryRecord? {
        queue.sync {
            let last = cachedLastRecord ?? loadRecordsUnsafe().last
            cachedLastRecord = last
            if let last,
               last.url == record.url,
               last.sessionID == record.sessionID,
               record.visitedAt.timeIntervalSince(last.visitedAt) < Self.deduplicationWindowSeconds {
                return nil
            }

            let existingCount = cachedRecordCount ?? countRecordsUnsafe()
            cachedRecordCount = existingCount

            if existingCount >= recordLimit {
                var records = loadRecordsUnsafe()
                records.append(record)
                records = Array(records.suffix(recordLimit))
                saveRecordsUnsafe(records)
            } else {
                appendRecordUnsafe(record)
                cachedRecordCount = existingCount + 1
                cachedLastRecord = record
            }
            return record
        }
    }

    /// Load all records sorted by `visitedAt` ascending.
    public func loadHistory() -> [BrowserHistoryRecord] {
        queue.sync { loadRecordsUnsafe() }
    }

    /// Search records by query string (matches URL, title, session title, or fetched page content, case-insensitive).
    public func searchHistory(query: String) -> [BrowserHistoryRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return loadHistory() }
        return queue.sync {
            loadRecordsUnsafe().filter { record in
                record.url.lowercased().contains(trimmed)
                    || record.title.lowercased().contains(trimmed)
                    || record.sessionTitle.lowercased().contains(trimmed)
                    || (record.contentMarkdown?.lowercased().contains(trimmed) ?? false)
            }
        }
    }

    /// Return a single history record by ID.
    public func record(id: UUID) -> BrowserHistoryRecord? {
        queue.sync { loadRecordsUnsafe().first { $0.id == id } }
    }

    /// Update fetched content for a previously appended history record.
    public func updateContent(
        id: UUID,
        markdown: String?,
        fetchedAt: Date = Date(),
        status: BrowserHistoryContentFetchStatus,
        error: String? = nil
    ) {
        queue.sync {
            var records = loadRecordsUnsafe()
            guard let index = records.firstIndex(where: { $0.id == id }) else { return }
            records[index].contentMarkdown = markdown
            records[index].contentFetchedAt = fetchedAt
            records[index].contentFetchStatus = status
            records[index].contentFetchError = error
            saveRecordsUnsafe(records)
        }
    }

    /// Delete a single record by ID.
    public func deleteRecord(id: UUID) {
        queue.sync {
            var records = loadRecordsUnsafe()
            records.removeAll { $0.id == id }
            saveRecordsUnsafe(records)
        }
    }

    /// Clear all history.
    public func clearHistory() {
        queue.sync {
            guard fileManager.fileExists(atPath: historyURL.path) else { return }
            try? fileManager.removeItem(at: historyURL)
            cachedRecordCount = 0
            cachedLastRecord = nil
        }
    }

    // MARK: - Private

    private func loadRecordsUnsafe() -> [BrowserHistoryRecord] {
        guard fileManager.fileExists(atPath: historyURL.path) else { return [] }
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [BrowserHistoryRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let record = try? decoder.decode(BrowserHistoryRecord.self, from: lineData)
            else { continue }
            records.append(record)
        }
        return records
    }

    private func countRecordsUnsafe() -> Int {
        guard fileManager.fileExists(atPath: historyURL.path) else { return 0 }
        guard let data = try? Data(contentsOf: historyURL), let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    private func appendRecordUnsafe(_ record: BrowserHistoryRecord) {
        let dir = historyURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(record), var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        guard let lineData = line.data(using: .utf8) else { return }

        if !fileManager.fileExists(atPath: historyURL.path) {
            fileManager.createFile(atPath: historyURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: historyURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: lineData)
    }

    private func saveRecordsUnsafe(_ records: [BrowserHistoryRecord]) {
        let dir = historyURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        for record in records {
            if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(to: historyURL, atomically: true, encoding: .utf8)
        cachedRecordCount = records.count
        cachedLastRecord = records.last
    }
}
