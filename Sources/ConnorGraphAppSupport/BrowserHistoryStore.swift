import Foundation
import ConnorGraphCore

public struct BrowserHistoryPage: Sendable, Equatable {
    public var records: [BrowserHistoryRecord]
    public var nextCursor: String?

    public init(records: [BrowserHistoryRecord], nextCursor: String?) {
        self.records = records
        self.nextCursor = nextCursor
    }
}

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

    /// Reads newest-first pages directly from the append-only JSONL file.
    /// The cursor is a byte offset, so loading older pages does not reread newer records.
    public func loadHistoryPage(cursor: String? = nil, query: String = "", pageSize: Int = 50) -> BrowserHistoryPage {
        queue.sync { loadHistoryPageUnsafe(cursor: cursor, query: query, pageSize: pageSize) }
    }

    /// Search records by query string (matches URL, title, session title, or fetched page content, case-insensitive).
    public func searchHistory(query: String) -> [BrowserHistoryRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return loadHistory() }
        let tokens = Self.searchTokens(for: trimmed)
        return queue.sync {
            loadRecordsUnsafe()
                .compactMap { record -> (BrowserHistoryRecord, Int)? in
                    let searchable = Self.searchableText(for: record)
                    if searchable.contains(trimmed) { return (record, max(tokens.count + 2, 3)) }
                    let tokenMatches = tokens.filter { searchable.localizedCaseInsensitiveContains($0) }.count
                    let requiredMatches = min(max(tokens.count, 1), 2)
                    guard tokenMatches >= requiredMatches else { return nil }
                    return (record, tokenMatches)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.0.visitedAt > rhs.0.visitedAt
                }
                .map(\.0)
        }
    }

    private static func searchTokens(for query: String) -> [String] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        let tokens = normalized.scoringTokens
            .map(\.value)
            .filter { $0.count >= 2 }
            .filter { query != $0 }
        var seen: Set<String> = []
        return tokens.filter { seen.insert($0).inserted }
    }

    private static func searchableText(for record: BrowserHistoryRecord) -> String {
        [
            record.url,
            record.title,
            record.sessionTitle,
            record.contentMarkdown ?? ""
        ].joined(separator: "\n").lowercased()
    }

    /// Return a single history record by ID.
    public func record(id: UUID) -> BrowserHistoryRecord? {
        queue.sync { loadRecordsUnsafe().first { $0.id == id } }
    }

    /// Update fetched content for a previously appended history record.
    @discardableResult
    public func updateContent(
        id: UUID,
        markdown: String?,
        fetchedAt: Date = Date(),
        status: BrowserHistoryContentFetchStatus,
        error: String? = nil
    ) -> BrowserHistoryRecord? {
        queue.sync {
            var records = loadRecordsUnsafe()
            guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            records[index].contentMarkdown = markdown
            records[index].contentFetchedAt = fetchedAt
            records[index].contentFetchStatus = status
            records[index].contentFetchError = error
            saveRecordsUnsafe(records)
            return records[index]
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

    private func loadHistoryPageUnsafe(cursor: String?, query: String, pageSize: Int) -> BrowserHistoryPage {
        guard fileManager.fileExists(atPath: historyURL.path),
              let handle = try? FileHandle(forReadingFrom: historyURL) else {
            return BrowserHistoryPage(records: [], nextCursor: nil)
        }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        var scanEnd = min(UInt64(cursor.flatMap(UInt64.init) ?? fileSize), fileSize)
        let resolvedPageSize = max(1, pageSize)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokens = Self.searchTokens(for: normalizedQuery)
        var carry = Data()
        var records: [BrowserHistoryRecord] = []
        var oldestIncludedOffset: UInt64?
        let chunkSize: UInt64 = 64 * 1_024

        while scanEnd > 0, records.count < resolvedPageSize {
            let start = scanEnd > chunkSize ? scanEnd - chunkSize : 0
            try? handle.seek(toOffset: start)
            var buffer = (try? handle.read(upToCount: Int(scanEnd - start))) ?? Data()
            buffer.append(carry)
            let bytes = [UInt8](buffer)
            var ranges: [Range<Int>] = []
            var lineStart = 0
            for index in bytes.indices where bytes[index] == 0x0A {
                ranges.append(lineStart..<index)
                lineStart = index + 1
            }
            if lineStart < bytes.count { ranges.append(lineStart..<bytes.count) }

            let firstCompleteIndex = start == 0 ? 0 : min(1, ranges.count)
            if firstCompleteIndex < ranges.count {
                for range in ranges[firstCompleteIndex...].reversed() where !range.isEmpty {
                    guard records.count < resolvedPageSize else { break }
                    let line = Data(bytes[range])
                    guard let record = try? decoder.decode(BrowserHistoryRecord.self, from: line),
                          normalizedQuery.isEmpty || Self.record(record, matches: normalizedQuery, tokens: tokens) else { continue }
                    records.append(record)
                    oldestIncludedOffset = start + UInt64(range.lowerBound)
                }
            }

            if start > 0 {
                if let firstRange = ranges.first {
                    carry = Data(bytes[firstRange])
                } else {
                    carry = buffer
                }
            }
            scanEnd = start
        }

        let nextCursor = records.count == resolvedPageSize
            ? oldestIncludedOffset.flatMap { $0 > 0 ? String($0) : nil }
            : nil
        return BrowserHistoryPage(records: records, nextCursor: nextCursor)
    }

    private static func record(_ record: BrowserHistoryRecord, matches query: String, tokens: [String]) -> Bool {
        let searchable = searchableText(for: record)
        if searchable.contains(query) { return true }
        let tokenMatches = tokens.filter { searchable.localizedCaseInsensitiveContains($0) }.count
        return tokenMatches >= min(max(tokens.count, 1), 2)
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
