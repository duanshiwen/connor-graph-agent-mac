import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppPromotionQueueRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var promotionService: MemoryPromotionService

    public init(store: SQLiteGraphKernelStore, promotionService: MemoryPromotionService = MemoryPromotionService()) {
        self.store = store
        self.promotionService = promotionService
    }

    public func loadCandidates(limit: Int = 100) throws -> [ObserveLogEntry] {
        []
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

        for entity in result.entities {
            try store.upsert(entity: entity)
        }
        for statement in result.statements {
            try store.upsert(statement: statement)
        }
        return result
    }

    @discardableResult
    public func dismiss(_ entry: ObserveLogEntry) throws -> ObserveLogEntry {
        promotionService.dismiss(entry)
    }

    @discardableResult
    public func pin(_ entry: ObserveLogEntry, now: Date = Date()) throws -> ObserveLogEntry {
        promotionService.pin(entry, at: now, additionalDays: 30)
    }
}
