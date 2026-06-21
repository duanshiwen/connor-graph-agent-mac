import Foundation
import ConnorGraphCore

public protocol NativeSourceSearchBackend: Sendable {
    func upsert(_ documents: [NativeSearchDocument]) async throws
    func delete(documentIDs: [String]) async throws
    func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String?) async throws
    func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String?, documents: [NativeSearchDocument]) async throws
    func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult]
    func health() async -> NativeSourceSearchHealthSnapshot
}

extension NativeSourceSearchService: NativeSourceSearchBackend {}
