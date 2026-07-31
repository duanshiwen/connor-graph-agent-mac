import Foundation
import ConnorGraphCore
import ConnorGraphStore

/// Projection-side alias resolution: forwarded-transcript tokens (`@CXxxxxxx`)
/// flowing out of L1 extraction are redirected to the real bound L4 person
/// entity, so facts accumulate on the person instead of spawning `@CX...`
/// garbage entities. Unresolvable tokens (e.g. senders without a bound person)
/// degrade to a plain name-based entity, exactly like Android's
/// `ProjectionApplier` behavior.
///
/// The Mac projection pipeline is deterministic and synchronous with no resolver
/// hook, so this rewriter runs as a batch post-processing step just before
/// `saveProjectionBatch` (wired through `AppMemoryOSFacade.projectionBatchRewriter`).
public struct ImForwardAliasProjectionRewriter {
    /// Token → memory entity id of the bound person; nil means unresolvable
    /// (missing alias row, unbound friend or the person entity does not exist),
    /// in which case the extracted entity is kept as-is.
    private let resolvePersonEntityID: (String) -> String?

    public init(resolvePersonEntityID: @escaping (String) -> String?) {
        self.resolvePersonEntityID = resolvePersonEntityID
    }

    /// Production wiring: alias token → `im_forward_alias` row → person profile
    /// binding → bound person memory entity (must already exist in the memory store).
    public init(imStore: SQLiteImStore, memoryStore: SQLiteMemoryOSStore) {
        self.init { token in
            guard let alias = try? imStore.forwardAlias(token: token) else { return nil }
            let stableKey = AppPersonMemoryBindingService.stableKey(for: ContactID(rawValue: alias.personProfileID))
            let entityID = AppPersonMemoryBindingService.entityID(forStableKey: stableKey)
            guard (try? memoryStore.entity(id: entityID)) != nil else { return nil }
            return entityID
        }
    }

    /// Rewrite a projection batch: L4 entities whose name carries a token and
    /// resolves to a bound person are removed (no `@CX` entity is created) and
    /// every entity statement referencing them is re-pointed at the person
    /// entity. L2 nodes keep the token verbatim — tokens intentionally flow
    /// as-is through L0/L1/L2; only the L4 identity layer resolves them.
    public func rewrite(_ batch: MemoryOSProjectionBatch) -> MemoryOSProjectionBatch {
        var redirects: [String: String] = [:]
        var entities: [MemoryOSEntity] = []
        entities.reserveCapacity(batch.entities.count)
        for entity in batch.entities {
            guard let target = resolvedTarget(forName: entity.name), target != entity.id else {
                entities.append(entity)
                continue
            }
            redirects[entity.id] = target
        }
        guard !redirects.isEmpty else { return batch }

        var rewritten = batch
        rewritten.entities = entities
        rewritten.entityStatements = batch.entityStatements.map { statement in
            var next = statement
            if let target = redirects[statement.entityID] { next.entityID = target }
            if let objectID = statement.objectEntityID, let target = redirects[objectID] {
                next.objectEntityID = target
            }
            return next
        }
        return rewritten
    }

    /// Name-carried token resolution, mirroring Android: try the raw trimmed name
    /// first, then its uppercased form (tolerates lowercased hex from the LLM).
    private func resolvedTarget(forName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = ImAliasTokens.firstToken(in: trimmed) ?? ImAliasTokens.firstToken(in: trimmed.uppercased())
        guard let token else { return nil }
        return resolvePersonEntityID(token)
    }
}
