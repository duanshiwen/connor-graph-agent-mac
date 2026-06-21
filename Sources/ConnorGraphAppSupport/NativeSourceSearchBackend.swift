import Foundation
import ConnorGraphCore

public protocol NativeSourceSearchBackend: Sendable {
    func upsert(_ documents: [NativeSearchDocument]) async throws
    func delete(documentIDs: [String]) async throws
    func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String?) async throws
    func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String?, documents: [NativeSearchDocument]) async throws
    func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult]
    func searchPage(_ request: NativeSearchPageRequest) async throws -> NativeSearchPage
    func health() async -> NativeSourceSearchHealthSnapshot
}

public extension NativeSourceSearchBackend {
    func searchPage(_ request: NativeSearchPageRequest) async throws -> NativeSearchPage {
        let backendKind = String(describing: Self.self)
        let signature = NativeSearchQuerySignature.signature(for: request.query)
        let offset: Int
        if let cursor = request.cursor {
            let payload = try NativeSearchCursorPayload.decode(cursor)
            guard payload.querySignature == signature else { throw NativeSearchPaginationError.queryChanged }
            offset = payload.offset
        } else {
            offset = 0
        }
        var expandedQuery = request.query
        expandedQuery.limit = NativeSearchLimitPolicy.clampSearchLimit(max(request.query.limit, offset + request.pageSize + 1))
        let allResults = try await search(expandedQuery)
        let pageResults = Array(allResults.dropFirst(offset).prefix(request.pageSize))
        let nextOffset = offset + pageResults.count
        let nextCursor: String?
        if nextOffset < allResults.count {
            nextCursor = try NativeSearchCursorPayload(
                backendKind: backendKind,
                querySignature: signature,
                offset: nextOffset,
                lastResultID: pageResults.last?.id
            ).encode()
        } else {
            nextCursor = nil
        }
        return NativeSearchPage(results: pageResults, nextCursor: nextCursor, totalAvailable: allResults.count)
    }
}

extension NativeSourceSearchService: NativeSourceSearchBackend {}
