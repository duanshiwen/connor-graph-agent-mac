import Foundation
import ConnorGraphCore

public struct MemoryOSPredicateLabel: Sendable, Codable, Equatable {
    public var predicate: String
    public var displayName: String
    public var forwardTemplate: String
    public var reverseTemplate: String?
    public var relationKind: String
    public var confidenceSemantics: String?

    public init(predicate: String, displayName: String, forwardTemplate: String, reverseTemplate: String? = nil, relationKind: String = "relation", confidenceSemantics: String? = nil) {
        self.predicate = predicate
        self.displayName = displayName
        self.forwardTemplate = forwardTemplate
        self.reverseTemplate = reverseTemplate
        self.relationKind = relationKind
        self.confidenceSemantics = confidenceSemantics
    }
}

public struct MemoryOSPredicateLabelRegistry: Sendable {
    public var labels: [String: MemoryOSPredicateLabel]

    public init(labels: [String: MemoryOSPredicateLabel] = MemoryOSPredicateLabelRegistry.defaultLabels) {
        self.labels = labels
    }

    public func label(for predicate: String) -> MemoryOSPredicateLabel {
        labels[predicate] ?? MemoryOSPredicateLabel(predicate: predicate, displayName: predicate.replacingOccurrences(of: "_", with: " "), forwardTemplate: "{source} relates to {target}")
    }

    public static let defaultLabels: [String: MemoryOSPredicateLabel] = {
        let values = [
            MemoryOSPredicateLabel(predicate: MemoryOSL4RelationPredicate.instanceOf.rawValue, displayName: "instance of", forwardTemplate: "{source} is an instance of {target}", relationKind: "taxonomy"),
            MemoryOSPredicateLabel(predicate: MemoryOSL4RelationPredicate.subclassOf.rawValue, displayName: "subclass of", forwardTemplate: "{source} is a subclass of {target}", relationKind: "taxonomy"),
            MemoryOSPredicateLabel(predicate: MemoryOSL4RelationPredicate.hasPart.rawValue, displayName: "has part", forwardTemplate: "{source} has part {target}", relationKind: "structural"),
            MemoryOSPredicateLabel(predicate: MemoryOSL4RelationPredicate.uses.rawValue, displayName: "uses", forwardTemplate: "{source} uses {target}", relationKind: "structural"),
            MemoryOSPredicateLabel(predicate: MemoryOSL4RelationPredicate.relatedTo.rawValue, displayName: "related to", forwardTemplate: "{source} is related to {target}"),
            MemoryOSPredicateLabel(predicate: "prefers", displayName: "prefers", forwardTemplate: "{source} prefers {target}", relationKind: "preference"),
            MemoryOSPredicateLabel(predicate: "dislikes", displayName: "dislikes", forwardTemplate: "{source} dislikes {target}", relationKind: "preference"),
            MemoryOSPredicateLabel(predicate: "hasGoal", displayName: "has goal", forwardTemplate: "{source} has goal {target}", relationKind: "profile"),
            MemoryOSPredicateLabel(predicate: "hasHabit", displayName: "has habit", forwardTemplate: "{source} has habit {target}", relationKind: "profile")
        ]
        return Dictionary(uniqueKeysWithValues: values.map { ($0.predicate, $0) })
    }()
}

public struct MemoryOSContextBuilder: Sendable {
    public var predicateLabels: MemoryOSPredicateLabelRegistry

    public init(predicateLabels: MemoryOSPredicateLabelRegistry = MemoryOSPredicateLabelRegistry()) {
        self.predicateLabels = predicateLabels
    }

    public func build(
        request: MemoryOSContextRequest,
        hits: [MemoryOSRetrievalHit],
        expansions: [String: [MemoryOSL4ExpansionHit]] = [:],
        generatedAt: Date = Date()
    ) -> MemoryOSContextPackage {
        let sortedHits = hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.layer.rawValue != rhs.layer.rawValue { return lhs.layer.rawValue < rhs.layer.rawValue }
            return lhs.recordID < rhs.recordID
        }

        var diagnostics: [MemoryOSContextDiagnostic] = []
        var blocks = makeBlocks(from: sortedHits, request: request)
        let allRelations = makeRelations(from: expansions)
        var entities = makeEntityCards(from: sortedHits, relations: allRelations)
        var evidence = makeEvidenceCards(from: sortedHits, limit: request.budget.maxEvidenceCards)

        let originalBlockCount = blocks.count
        let originalRelationCount = allRelations.count
        blocks = Array(blocks.prefix(request.budget.maxBlocks))
        let relations = Array(allRelations.prefix(request.budget.maxRelationCards))
        entities = Array(entities.prefix(request.budget.maxEntityCards))
        evidence = Array(evidence.prefix(request.budget.maxEvidenceCards))

        let preliminaryText = renderContextText(request: request, blocks: blocks, entities: entities, relations: relations, evidence: evidence)
        let budgetedText = preliminaryText

        let truncatedBlocks = max(0, originalBlockCount - blocks.count)
        let truncatedRelations = max(0, originalRelationCount - relations.count)
        if truncatedBlocks > 0 || truncatedRelations > 0 {
            diagnostics.append(MemoryOSContextDiagnostic(
                id: "budget-truncated",
                severity: .warning,
                kind: .budgetTruncated,
                message: "Memory context was truncated to fit item limits.",
                affectedRecordIDs: blocks.flatMap(\.recordIDs),
                suggestedAction: "Use a narrower query to reduce result count."
            ))
        }
        if hits.isEmpty {
            diagnostics.append(MemoryOSContextDiagnostic(id: "no-relevant-memory", severity: .info, kind: .noRelevantMemory, message: "No relevant Memory OS records were retrieved."))
        }

        let evidenceBearingBlocks = blocks.filter { !$0.evidenceRefs.isEmpty }.count
        let evidenceCoverage = blocks.isEmpty ? 0 : Double(evidenceBearingBlocks) / Double(blocks.count)
        let relationCoverage = allRelations.isEmpty ? 0 : Double(relations.count) / Double(allRelations.count)
        let budgetCompliance: Double = 1.0

        return MemoryOSContextPackage(
            id: "memory-context-\(stableContextIDSeed(query: request.query, generatedAt: generatedAt))",
            query: request.query,
            taskIntent: request.taskIntent,
            generatedAt: generatedAt,
            referenceTime: request.referenceTime,
            executiveSummary: makeExecutiveSummary(request: request, blocks: blocks, entities: entities, relations: relations),
            contextText: budgetedText,
            blocks: blocks,
            entities: entities,
            relations: relations,
            evidence: evidence,
            diagnostics: diagnostics,
            rawRetrieval: MemoryOSRawRetrievalTrace(
                initialHitCount: hits.count,
                expandedRelationCount: allRelations.count,
                tracedEvidenceCount: evidence.count,
                retrievalMethods: ["memory_os_unified_retrieval", expansions.isEmpty ? "no_graph_expansion" : "l4_expansion"]
            ),
            suggestedNextActions: makeNextActions(from: sortedHits, evidence: evidence),
            budgetReport: MemoryOSContextBudgetReport(
                maxContextCharacters: request.budget.maxContextCharacters,
                actualContextCharacters: budgetedText.count,
                truncatedBlockCount: truncatedBlocks,
                truncatedRelationCount: truncatedRelations
            ),
            qualitySignals: MemoryOSContextQualitySignals(
                relevanceScore: sortedHits.first?.score ?? 0,
                evidenceCoverage: evidenceCoverage,
                relationCoverage: relationCoverage,
                redundancyRate: 0,
                staleLeakRate: 0,
                conflictSurfacingRate: diagnostics.contains { $0.kind == .conflictingFacts } ? 1 : 0,
                budgetCompliance: budgetCompliance
            )
        )
    }

    private func makeBlocks(from hits: [MemoryOSRetrievalHit], request: MemoryOSContextRequest) -> [MemoryOSContextBlock] {
        hits.enumerated().map { index, hit in
            let role = role(for: hit, request: request)
            let text = blockText(for: hit)
            let evidenceRefs = Array(hit.evidenceRefs.prefix(request.budget.maxEvidenceRefsPerBlock))
            return MemoryOSContextBlock(
                id: "block-\(hit.layer.rawValue)-\(hit.recordID)",
                role: role,
                layer: hit.layer,
                priority: priority(for: role, index: index),
                text: text,
                recordIDs: [hit.recordID],
                entityIDs: hit.entityRefs,
                relationIDs: hit.layer == .l4 && !hit.entityRefs.isEmpty && hit.metadata["entity_type"] == nil ? [hit.recordID] : [],
                evidenceRefs: evidenceRefs,
                provenanceRefs: hit.provenanceRefs,
                confidence: Double(hit.metadata["confidence"] ?? ""),
                uncertainty: hit.score < 0.5 ? .medium : .low
            )
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }

    private func makeEntityCards(from hits: [MemoryOSRetrievalHit], relations: [MemoryOSRelationContextCard]) -> [MemoryOSEntityContextCard] {
        var cards: [String: MemoryOSEntityContextCard] = [:]
        for hit in hits where hit.layer == .l4 && hit.metadata["entity_type"] != nil {
            let entityID = hit.entityRefs.first ?? hit.recordID
            let outgoing = relations.filter { $0.sourceID == entityID }.map(\.id)
            let incoming = relations.filter { $0.targetID == entityID }.map(\.id)
            cards[entityID] = MemoryOSEntityContextCard(
                id: "entity-card-\(entityID)",
                entityID: entityID,
                name: hit.title,
                kind: hit.metadata["entity_type"] ?? "entity",
                summary: hit.summary,
                aliases: [],
                attributes: hit.summary.isEmpty ? [] : [MemoryOSAttributeSentence(text: hit.summary, recordIDs: [hit.recordID], evidenceRefs: hit.evidenceRefs)],
                outgoingRelations: outgoing,
                incomingRelations: incoming,
                evidenceRefs: hit.evidenceRefs,
                provenanceRefs: hit.provenanceRefs,
                sourceRecordIDs: [hit.recordID]
            )
        }
        return cards.values.sorted { $0.name < $1.name }
    }

    private func makeRelations(from expansions: [String: [MemoryOSL4ExpansionHit]]) -> [MemoryOSRelationContextCard] {
        expansions.values.flatMap { $0 }.filter { hit in
            hit.sourceEntityID != hit.relatedEntityID && hit.relatedEntityID != nil
        }.sorted { lhs, rhs in
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            return lhs.recordID < rhs.recordID
        }.map { hit in
            let label = predicateLabels.label(for: hit.predicate)
            return MemoryOSRelationContextCard(
                id: hit.recordID,
                sourceID: hit.sourceEntityID,
                sourceName: nil,
                predicate: hit.predicate,
                predicateLabel: label.displayName,
                targetID: hit.relatedEntityID,
                targetName: nil,
                sentence: hit.text.isEmpty ? renderRelationSentence(source: hit.sourceEntityID, predicate: label, target: hit.relatedEntityID ?? "unknown") : hit.text,
                confidence: hit.score,
                evidenceRefs: [],
                provenanceRefs: []
            )
        }
    }

    private func makeEvidenceCards(from hits: [MemoryOSRetrievalHit], limit: Int) -> [MemoryOSEvidenceContextCard] {
        var seen = Set<String>()
        var cards: [MemoryOSEvidenceContextCard] = []
        for hit in hits {
            for ref in hit.evidenceRefs where !seen.contains(ref) {
                seen.insert(ref)
                cards.append(MemoryOSEvidenceContextCard(
                    id: "evidence-\(ref)",
                    evidenceRef: ref,
                    provenanceRef: hit.provenanceRefs.first,
                    snippet: hit.matchedText.isEmpty ? hit.summary : hit.matchedText,
                    sourceTitle: hit.title,
                    quality: hit.score
                ))
                if cards.count >= limit { return cards }
            }
        }
        return cards
    }

    private func renderContextText(request: MemoryOSContextRequest, blocks: [MemoryOSContextBlock], entities: [MemoryOSEntityContextCard], relations: [MemoryOSRelationContextCard], evidence: [MemoryOSEvidenceContextCard]) -> String {
        var lines: [String] = []
        lines.append("## Memory OS Context")
        lines.append("Query: \(request.query)")
        lines.append("Intent: \(request.taskIntent.rawValue)")
        if !entities.isEmpty {
            lines.append("\n### Entities")
            for entity in entities {
                lines.append("- \(entity.name) [\(entity.kind)]: \(entity.summary)")
            }
        }
        if !relations.isEmpty {
            lines.append("\n### Relations")
            for relation in relations {
                lines.append("- \(relation.sentence) (predicate: \(relation.predicateLabel), id: \(relation.id))")
            }
        }
        if !blocks.isEmpty {
            lines.append("\n### Context Blocks")
            for block in blocks {
                let evidenceSuffix = block.evidenceRefs.isEmpty ? "" : " Evidence: \(block.evidenceRefs.joined(separator: ", "))"
                lines.append("- [\(block.role.rawValue)] \(block.text)\(evidenceSuffix)")
            }
        }
        if !evidence.isEmpty {
            lines.append("\n### Evidence")
            for card in evidence {
                lines.append("- \(card.evidenceRef): \(card.snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func makeExecutiveSummary(request: MemoryOSContextRequest, blocks: [MemoryOSContextBlock], entities: [MemoryOSEntityContextCard], relations: [MemoryOSRelationContextCard]) -> String {
        if blocks.isEmpty && entities.isEmpty && relations.isEmpty {
            return "No Memory OS context was found for query: \(request.query)."
        }
        return "Memory OS context for '\(request.query)' contains \(blocks.count) block(s), \(entities.count) entity card(s), and \(relations.count) relation card(s)."
    }

    private func makeNextActions(from hits: [MemoryOSRetrievalHit], evidence: [MemoryOSEvidenceContextCard]) -> [MemoryOSContextNextAction] {
        var actions: [MemoryOSContextNextAction] = []
        if let expandable = hits.first(where: { $0.canExpandDepth }), let entityID = expandable.entityRefs.first ?? Optional(expandable.recordID) {

        }
        if !evidence.isEmpty {
        }
        return actions
    }

    private func role(for hit: MemoryOSRetrievalHit, request: MemoryOSContextRequest) -> MemoryOSContextRole {
        if request.taskIntent == .currentUserPersonalization { return .currentUserProfile }
        switch hit.layer {
        case .l0, .l1: return .evidence
        case .l2: return .operationalFact
        case .l3: return .reusableKnowledge
        case .l4:
            return hit.metadata["entity_type"] == nil ? .relation : .stableEntity
        }
    }

    private func priority(for role: MemoryOSContextRole, index: Int) -> Int {
        let base: Int
        switch role {
        case .currentUserProfile: base = 100
        case .projectState: base = 90
        case .operationalFact: base = 80
        case .relation: base = 75
        case .stableEntity: base = 70
        case .reusableKnowledge: base = 65
        case .evidence: base = 60
        case .conflict: base = 95
        case .uncertainty: base = 50
        case .historicalContext: base = 40
        case .nextStepHint: base = 30
        }
        return base - index
    }

    private func blockText(for hit: MemoryOSRetrievalHit) -> String {
        let text = hit.matchedText.isEmpty ? hit.summary : hit.matchedText
        switch hit.layer {
        case .l0: return "Raw provenance \(hit.title): \(text)"
        case .l1: return "Capture event \(hit.title): \(text)"
        case .l2: return "Operational fact \(hit.title): \(text)"
        case .l3: return "Reusable knowledge \(hit.title): \(text)"
        case .l4:
            if let entityType = hit.metadata["entity_type"] {
                return "Stable entity \(hit.title) [\(entityType)]: \(hit.summary.isEmpty ? text : hit.summary)"
            }
            return "L4 relation or attribute \(hit.title): \(text)"
        }
    }

    private func renderRelationSentence(source: String, predicate: MemoryOSPredicateLabel, target: String) -> String {
        predicate.forwardTemplate
            .replacingOccurrences(of: "{source}", with: source)
            .replacingOccurrences(of: "{target}", with: target)
    }

    private func stableContextIDSeed(query: String, generatedAt: Date) -> String {
        let sanitized = query.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24)
        return "\(sanitized)-\(Int(generatedAt.timeIntervalSince1970))"
    }

    /// Build a flat array of natural-language strings from retrieval hits and L4 graph expansions.
    /// - Parameters:
    ///   - hits: Merged and sorted retrieval hits from all sub-queries.
    ///   - expansions: L4 graph expansion results keyed by entity ID.
    /// - Returns: Deduplicated array of natural-language memory items.
    public func buildFlatStrings(
        hits: [MemoryOSRetrievalHit],
        expansions: [String: [MemoryOSL4ExpansionHit]],
        extraEntityNames: [String: String] = [:]
    ) -> [String] {
        let sortedHits = hits.sorted { $0.score > $1.score }

        // Build entityID → name map from L4 entity hits
        var entityIDToName: [String: String] = [:]
        for hit in sortedHits where hit.layer == .l4 && hit.metadata["entity_type"] != nil {
            let entityID = hit.entityRefs.first ?? hit.recordID
            entityIDToName[entityID] = hit.title
        }

        var seen: Set<String> = []
        var result: [String] = []

        func append(_ string: String) {
            guard !seen.contains(string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            seen.insert(string)
            result.append(string)
        }

        // Flatten hits
        for hit in sortedHits {
            switch hit.layer {
            case .l0:
                continue // L0 is not included per design
            case .l1:
                append("Capture event「\(hit.title)」: \(hit.matchedText)")
            case .l2:
                append(hit.matchedText)
            case .l3:
                append(hit.matchedText)
            case .l4:
                if let entityType = hit.metadata["entity_type"] {
                    let text = hit.summary.isEmpty ? hit.matchedText : hit.summary
                    append("「\(hit.title)」(\(entityType)): \(text)")
                }
                // L4 relation hits without entity_type are skipped (relations come from expansions)
            }
        }

        // Flatten expansion relations
        for (_, relations) in expansions {
            for relation in relations {
                // Skip self-referencing relations (e.g. "X is a subclass of X")
                guard relation.sourceEntityID != relation.relatedEntityID else { continue }
                // Skip nil-target relations (renders as "X relates to unknown")
                guard relation.relatedEntityID != nil else { continue }
                let sourceName = extraEntityNames[relation.sourceEntityID] ?? entityIDToName[relation.sourceEntityID] ?? relation.sourceEntityID
                let targetName = extraEntityNames[relation.relatedEntityID!] ?? entityIDToName[relation.relatedEntityID!] ?? relation.relatedEntityID!
                let label = predicateLabels.label(for: relation.predicate)
                let sentence = label.forwardTemplate
                    .replacingOccurrences(of: "{source}", with: sourceName)
                    .replacingOccurrences(of: "{target}", with: targetName)
                append(sentence)
            }
        }

        return result
    }
}
