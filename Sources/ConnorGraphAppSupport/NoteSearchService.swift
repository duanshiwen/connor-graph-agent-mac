import Foundation
import ConnorGraphCore

public enum NoteSearchServiceError: Error, Sendable, Equatable {
    case invalidDateRange
    case invalidPage(Int)
}

public struct NoteSearchService: Sendable {
    public static let currentIndexVersion = 1
    public static let defaultPageSize = 10
    public let repository: AppNoteRepository

    public init(repository: AppNoteRepository) { self.repository = repository }

    public func index(_ note: NoteRecord) throws {
        let indexedText = NativeSourceSearchIndexedTextBuilder.searchableText(title: note.title, body: note.body)
        try repository.upsertSearchDocument(note, indexedText: indexedText, indexVersion: Self.currentIndexVersion)
    }

    public func search(query: String, startDate: Date? = nil, endDate: Date? = nil, originKind: NoteOriginKind? = nil, page: Int = 1, pageSize: Int = defaultPageSize) throws -> NoteSearchPage {
        guard page >= 1 else { throw NoteSearchServiceError.invalidPage(page) }
        guard startDate == nil || endDate == nil || startDate! < endDate! else { throw NoteSearchServiceError.invalidDateRange }
        let parsed = MemorySearchQueryParser.parse(query).terms.joined(separator: " ")
        let normalized = NativeSearchQueryNormalizer.normalize(parsed)
        let match = NativeSourceSearchFTSQueryBuilder.query(for: normalized)
        let effectivePageSize = min(max(pageSize, 1), 50)
        let result = try repository.search(
            matchQuery: match.isEmpty ? nil : match, matchedTerms: normalized.displayTokenValues,
            startDate: startDate, endDate: endDate, originKind: originKind, page: page, pageSize: effectivePageSize
        )
        let totalPages = result.totalItems == 0 ? 0 : (result.totalItems + effectivePageSize - 1) / effectivePageSize
        guard page <= max(totalPages, 1) else { throw NoteSearchServiceError.invalidPage(page) }
        return result
    }
}

public actor NoteIndexReconciler {
    private let repository: AppNoteRepository
    private let search: NoteSearchService
    private let batchSize: Int

    public init(repository: AppNoteRepository, batchSize: Int = 25) {
        self.repository = repository
        self.search = NoteSearchService(repository: repository)
        self.batchSize = min(max(batchSize, 1), 100)
    }

    public func reconcile(maxBatches: Int = 8) async -> NoteProjectionReconciliationResult {
        var indexed = 0
        var failed = 0
        var hasMore = false
        for _ in 0..<max(maxBatches, 1) {
            guard !Task.isCancelled else { break }
            let notes: [NoteRecord]
            do { notes = try repository.notesNeedingIndex(version: NoteSearchService.currentIndexVersion, limit: batchSize) }
            catch { failed += 1; break }
            if notes.isEmpty { hasMore = false; break }
            hasMore = notes.count == batchSize
            for note in notes {
                guard !Task.isCancelled else { hasMore = true; break }
                do { try search.index(note); indexed += 1 } catch { failed += 1 }
            }
            await Task.yield()
        }
        return NoteProjectionReconciliationResult(projected: indexed, removed: 0, failed: failed, hasMore: hasMore)
    }
}
