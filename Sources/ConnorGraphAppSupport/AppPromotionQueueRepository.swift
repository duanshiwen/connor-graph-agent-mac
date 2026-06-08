import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppPromotionQueueRepository: @unchecked Sendable {
    public let store: SQLiteGraphStore
    public var promotionService: MemoryPromotionService

    public init(store: SQLiteGraphStore, promotionService: MemoryPromotionService = MemoryPromotionService()) {
        self.store = store
        self.promotionService = promotionService
    }

    public func loadCandidates(limit: Int = 100) throws -> [ObserveLogEntry] {
        try store.promotionCandidates(limit: limit)
    }

    @discardableResult
    public func promote(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        let result: MemoryPromotionResult
        switch entry.kind {
        case .candidateFact:
            result = try promotionService.promoteCandidateFact(entry)
        case .decisionHint:
            result = try promotionService.promoteDecisionHint(entry)
        case .userPreference:
            result = try promotionService.promoteUserPreference(entry)
        default:
            throw MemoryPromotionError.unsupportedKind(expected: .candidateFact, actual: entry.kind)
        }

        for node in result.nodes {
            try store.upsert(node: node)
        }
        for edge in result.edges {
            try store.upsert(edge: edge)
        }
        try store.update(observeLogEntry: result.promotedEntry)
        return result
    }

    @discardableResult
    public func dismiss(_ entry: ObserveLogEntry) throws -> ObserveLogEntry {
        let dismissed = promotionService.dismiss(entry)
        try store.update(observeLogEntry: dismissed)
        return dismissed
    }

    @discardableResult
    public func pin(_ entry: ObserveLogEntry, now: Date = Date()) throws -> ObserveLogEntry {
        let pinned = promotionService.pin(entry, at: now, additionalDays: 30)
        try store.update(observeLogEntry: pinned)
        return pinned
    }
}
