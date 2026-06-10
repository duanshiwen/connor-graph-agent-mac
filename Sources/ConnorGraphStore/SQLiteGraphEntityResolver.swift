import Foundation
import ConnorGraphCore

public enum GraphEntityResolverMatchReason: String, Codable, Sendable, Equatable {
    case stableKey
    case alias
    case fts
}

public enum GraphEntityResolverResult: Sendable, Equatable {
    case matched(String, reason: GraphEntityResolverMatchReason)
    case create(stableKey: String)
    case potentialDuplicate(String, reason: GraphEntityResolverMatchReason)
}

public struct SQLiteGraphEntityResolver: Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func resolve(name: String, entityKind: GraphEntityKind, scope: GraphScope, graphID: String) throws -> GraphEntityResolverResult {
        let stableKey = GraphStableKeyBuilder.stableKey(scope: scope, entityKind: entityKind, name: name)
        if let entity = try store.entity(stableKey: stableKey, graphID: graphID) {
            return .matched(entity.id, reason: .stableKey)
        }

        let normalizedInput = GraphStableKeyBuilder.normalized(name)
        let scopedEntities = try store.entities(graphID: graphID, scope: scope, entityKind: entityKind)
        if let aliasMatch = scopedEntities.first(where: { entity in
            entity.aliases.contains { GraphStableKeyBuilder.normalized($0) == normalizedInput }
        }) {
            return .matched(aliasMatch.id, reason: .alias)
        }

        let ftsMatches = try store.searchEntitiesFTS(query: name, graphID: graphID, limit: 5)
            .filter { $0.scope == scope && $0.entityKind == entityKind }
        if let exactFTS = ftsMatches.first(where: { GraphStableKeyBuilder.normalized($0.name) == normalizedInput }) {
            return .matched(exactFTS.id, reason: .fts)
        }
        if let potential = ftsMatches.first {
            return .potentialDuplicate(potential.id, reason: .fts)
        }

        return .create(stableKey: stableKey)
    }
}
