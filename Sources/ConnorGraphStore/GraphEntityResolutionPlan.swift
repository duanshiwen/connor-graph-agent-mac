import Foundation
import ConnorGraphCore

public enum GraphEntityResolutionPlanEntryAction: String, Codable, Sendable, Equatable {
    case matched
    case create
    case potentialDuplicate = "potential_duplicate"
}

public struct GraphEntityResolutionPlanEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { localID }
    public var localID: String
    public var name: String
    public var entityKind: GraphEntityKind
    public var scope: GraphScope
    public var action: GraphEntityResolutionPlanEntryAction
    public var matchedEntityID: String?
    public var stableKey: String?
    public var reason: GraphEntityResolverMatchReason?

    public init(
        localID: String,
        name: String,
        entityKind: GraphEntityKind,
        scope: GraphScope,
        action: GraphEntityResolutionPlanEntryAction,
        matchedEntityID: String? = nil,
        stableKey: String? = nil,
        reason: GraphEntityResolverMatchReason? = nil
    ) {
        self.localID = localID
        self.name = name
        self.entityKind = entityKind
        self.scope = scope
        self.action = action
        self.matchedEntityID = matchedEntityID
        self.stableKey = stableKey
        self.reason = reason
    }
}

public struct GraphEntityResolutionPlan: Codable, Sendable, Equatable {
    public var entries: [GraphEntityResolutionPlanEntry]

    public init(entries: [GraphEntityResolutionPlanEntry] = []) {
        self.entries = entries
    }

    public var matchedCount: Int { entries.filter { $0.action == .matched }.count }
    public var createCount: Int { entries.filter { $0.action == .create }.count }
    public var potentialDuplicateCount: Int { entries.filter { $0.action == .potentialDuplicate }.count }
    public var hasPotentialDuplicates: Bool { potentialDuplicateCount > 0 }

    public var traceMetadata: [String: String] {
        var metadata: [String: String] = [
            "entity_resolution_matched_count": String(matchedCount),
            "entity_resolution_create_count": String(createCount),
            "entity_resolution_potential_duplicate_count": String(potentialDuplicateCount)
        ]
        let compact = entries.map { entry in
            [
                entry.localID,
                entry.action.rawValue,
                entry.matchedEntityID ?? entry.stableKey ?? "",
                entry.reason?.rawValue ?? ""
            ].joined(separator: ":")
        }.joined(separator: ",")
        if !compact.isEmpty {
            metadata["entity_resolution_plan"] = compact
        }
        return metadata
    }
}

public struct GraphEntityResolutionPlanner: Sendable {
    public var resolver: SQLiteGraphEntityResolver

    public init(resolver: SQLiteGraphEntityResolver) {
        self.resolver = resolver
    }

    public func plan(for draft: GraphExtractionDraft) throws -> GraphEntityResolutionPlan {
        let entries = try draft.entities.map { entity in
            let result = try resolver.resolve(
                name: entity.name,
                entityKind: entity.entityKind,
                scope: entity.scope,
                graphID: draft.source.graphID
            )
            switch result {
            case .matched(let entityID, let reason):
                return GraphEntityResolutionPlanEntry(
                    localID: entity.localID,
                    name: entity.name,
                    entityKind: entity.entityKind,
                    scope: entity.scope,
                    action: .matched,
                    matchedEntityID: entityID,
                    reason: reason
                )
            case .create(let stableKey):
                return GraphEntityResolutionPlanEntry(
                    localID: entity.localID,
                    name: entity.name,
                    entityKind: entity.entityKind,
                    scope: entity.scope,
                    action: .create,
                    stableKey: stableKey
                )
            case .potentialDuplicate(let entityID, let reason):
                return GraphEntityResolutionPlanEntry(
                    localID: entity.localID,
                    name: entity.name,
                    entityKind: entity.entityKind,
                    scope: entity.scope,
                    action: .potentialDuplicate,
                    matchedEntityID: entityID,
                    reason: reason
                )
            }
        }
        return GraphEntityResolutionPlan(entries: entries)
    }
}

public extension GraphExtractionDraft {
    func withEntityResolutionPlanMetadata(_ plan: GraphEntityResolutionPlan) -> GraphExtractionDraft {
        var copy = self
        for (key, value) in plan.traceMetadata {
            copy.metadata[key] = value
        }
        return copy
    }
}
