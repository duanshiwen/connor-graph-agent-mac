import Foundation
import ConnorGraphCore

public enum MemoryPromotionError: Error, Equatable, Sendable {
    case unsupportedKind(expected: ObserveLogKind, actual: ObserveLogKind)
    case missingRelatedNodes(required: Int, actual: Int)
    case missingPersonNode
}

public struct MemoryPromotionResult: Sendable, Equatable {
    public var nodes: [GraphNode]
    public var edges: [SemanticEdge]
    public var promotedEntry: ObserveLogEntry

    public init(nodes: [GraphNode], edges: [SemanticEdge], promotedEntry: ObserveLogEntry) {
        self.nodes = nodes
        self.edges = edges
        self.promotedEntry = promotedEntry
    }
}

public struct MemoryPromotionService: Sendable, Equatable {
    public init() {}

    public func promoteCandidateFact(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .candidateFact else {
            throw MemoryPromotionError.unsupportedKind(expected: .candidateFact, actual: entry.kind)
        }
        guard entry.relatedNodeIDs.count >= 2 else {
            throw MemoryPromotionError.missingRelatedNodes(required: 2, actual: entry.relatedNodeIDs.count)
        }

        let sourceID = entry.relatedNodeIDs[0]
        let targetID = entry.relatedNodeIDs[1]
        let edge = SemanticEdge(
            id: "edge-promoted-\(entry.id)",
            sourceNodeID: sourceID,
            targetNodeID: targetID,
            relation: .relatedTo,
            fact: entry.content,
            confidence: entry.confidence,
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )

        return MemoryPromotionResult(nodes: [], edges: [edge], promotedEntry: entry.promoted(toNodeID: edge.id))
    }

    public func promoteDecisionHint(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .decisionHint else {
            throw MemoryPromotionError.unsupportedKind(expected: .decisionHint, actual: entry.kind)
        }

        let node = GraphNode(
            id: "decision-\(slug(entry.content))",
            type: .decision,
            title: entry.content,
            summary: entry.normalizedSummary,
            status: .draft,
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )
        var edges: [SemanticEdge] = []
        if let workObjectID = entry.workObjectID {
            edges.append(SemanticEdge(
                id: "edge-\(node.id)-belongs-to-\(workObjectID)",
                sourceNodeID: node.id,
                targetNodeID: workObjectID,
                relation: .belongsTo,
                fact: "\(node.title) belongs to \(workObjectID)",
                confidence: entry.confidence,
                metadata: ["promoted_from": entry.id]
            ))
        }

        return MemoryPromotionResult(nodes: [node], edges: edges, promotedEntry: entry.promoted(toNodeID: node.id))
    }

    public func promoteUserPreference(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .userPreference else {
            throw MemoryPromotionError.unsupportedKind(expected: .userPreference, actual: entry.kind)
        }
        guard let personID = entry.relatedNodeIDs.first else {
            throw MemoryPromotionError.missingPersonNode
        }

        let node = GraphNode(
            id: "preference-\(slug(entry.content))",
            type: .preference,
            title: entry.content,
            summary: entry.normalizedSummary,
            status: .draft,
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )
        let edge = SemanticEdge(
            id: "edge-\(personID)-has-preference-\(node.id)",
            sourceNodeID: personID,
            targetNodeID: node.id,
            relation: .hasPreference,
            fact: entry.content,
            confidence: entry.confidence,
            metadata: ["promoted_from": entry.id]
        )

        return MemoryPromotionResult(nodes: [node], edges: [edge], promotedEntry: entry.promoted(toNodeID: node.id))
    }

    public func dismiss(_ entry: ObserveLogEntry) -> ObserveLogEntry {
        var copy = entry
        copy.status = .dismissed
        copy.promotedNodeID = nil
        return copy
    }

    public func pin(_ entry: ObserveLogEntry, at date: Date = Date(), additionalDays: Int = 30) -> ObserveLogEntry {
        var copy = entry
        copy.status = .active
        copy.expiresAt = date.addingTimeInterval(TimeInterval(additionalDays) * 24 * 60 * 60)
        return copy
    }

    private func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var output = ""
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else {
                output.append("-")
            }
        }
        while output.contains("--") {
            output = output.replacingOccurrences(of: "--", with: "-")
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(80))
    }
}
