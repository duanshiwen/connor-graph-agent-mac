import Foundation
import ConnorGraphCore

public enum MemoryOSContextRole: String, Codable, Sendable, Equatable, CaseIterable {
    case operational
    case belief
    case knowledge
    case entity
    case evidence
    case conflict
}

public struct MemoryOSContextItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: MemoryOSContextRole
    public var content: String
    public var evidenceIDs: [String]
    public var score: Double

    public init(id: String, role: MemoryOSContextRole, content: String, evidenceIDs: [String] = [], score: Double = 0.5) {
        self.id = id; self.role = role; self.content = content; self.evidenceIDs = evidenceIDs; self.score = score
    }
}

public struct MemoryOSContextContract: Codable, Sendable, Equatable {
    public var query: String
    public var generatedAt: Date
    public var items: [MemoryOSContextItem]
    public var hasStaleSignals: Bool
    public var hasConflictSignals: Bool
    public var hasUncertaintySignals: Bool
    public var tokenEstimate: Int

    public init(query: String, generatedAt: Date = Date(), items: [MemoryOSContextItem] = [], hasStaleSignals: Bool = false, hasConflictSignals: Bool = false, hasUncertaintySignals: Bool = false, tokenEstimate: Int = 0) {
        self.query = query; self.generatedAt = generatedAt; self.items = items; self.hasStaleSignals = hasStaleSignals; self.hasConflictSignals = hasConflictSignals; self.hasUncertaintySignals = hasUncertaintySignals; self.tokenEstimate = tokenEstimate
    }

    public var renderedText: String {
        guard !items.isEmpty else { return "" }
        return items.sorted { $0.score > $1.score }.map { item in
            "- [\(item.role.rawValue)] \(item.content)"
        }.joined(separator: "\n")
    }
}

public struct MemoryOSContextCompiler: Sendable {
    public var tokenBudget: Int

    public init(tokenBudget: Int = 2_000) {
        self.tokenBudget = tokenBudget
    }

    public func compile(query: String, statements: [MemoryOSStatement], beliefs: [MemoryOSBelief], entities: [MemoryOSEntity], now: Date = Date()) -> MemoryOSContextContract {
        var items: [MemoryOSContextItem] = []
        items += statements.map { statement in
            MemoryOSContextItem(id: statement.id, role: .operational, content: statement.text, evidenceIDs: statement.evidenceSpanIDs, score: statement.confidence)
        }
        items += beliefs.map { belief in
            MemoryOSContextItem(id: belief.id, role: .knowledge, content: belief.statement, evidenceIDs: [], score: 1.0)
        }
        items += entities.map { entity in
            MemoryOSContextItem(id: entity.id, role: .entity, content: "\(entity.name): \(entity.summary)", score: entity.confidence)
        }
        let sorted = items.sorted { $0.score > $1.score }
        var selected: [MemoryOSContextItem] = []
        var tokens = 0
        for item in sorted {
            let estimate = max(1, item.content.count / 4)
            guard tokens + estimate <= tokenBudget else { continue }
            selected.append(item)
            tokens += estimate
        }
        return MemoryOSContextContract(query: query, generatedAt: now, items: selected, hasConflictSignals: items.contains { $0.role == .conflict }, hasUncertaintySignals: items.contains { $0.score < 0.5 }, tokenEstimate: tokens)
    }
}

public struct MemoryOSReadTools: Sendable {
    public init() {}

    public func renderEntityProfile(_ entity: MemoryOSEntity) -> String {
        let aliases = entity.aliases.isEmpty ? "" : " aliases: \(entity.aliases.joined(separator: ", "))"
        return "\(entity.name) [\(entity.entityType)]\(aliases) — \(entity.summary)"
    }
}

public struct MemoryOSWriteTools: Sendable {
    public init() {}

    public func makeObservation(subjectID: String, predicate: String, text: String, evidenceSpanIDs: [String], now: Date = Date()) -> MemoryOSStatement {
        MemoryOSStatement(subjectID: subjectID, predicate: predicate, text: text, assertionKind: .observed, confidence: 0.7, validAt: now, committedAt: now, evidenceSpanIDs: evidenceSpanIDs)
    }

    public func proposeBelief(topic: String, statement: String, evidenceStatementIDs: [String] = [], now: Date = Date()) -> MemoryOSBelief {
        MemoryOSBelief(statement: statement, domain: topic, createdAt: now, updatedAt: now)
    }
}
