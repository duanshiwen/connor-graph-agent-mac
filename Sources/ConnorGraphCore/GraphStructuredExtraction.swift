import Foundation

public struct GraphStructuredEvidenceSpan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var startOffset: Int?
    public var endOffset: Int?

    public init(id: String, text: String, startOffset: Int? = nil, endOffset: Int? = nil) {
        self.id = id
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct GraphStructuredExtractionWarning: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var code: String
    public var message: String
    public var severity: String

    public init(id: String, code: String, message: String, severity: String = "warning") {
        self.id = id
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct GraphStructuredExtractedEntity: Codable, Sendable, Equatable, Identifiable {
    public var id: String { localID }
    public var localID: String
    public var name: String
    public var entityKind: GraphEntityKind
    public var scope: GraphScope
    public var canonicalClassID: String?
    public var aliases: [String]
    public var summary: String
    public var confidence: Double
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]

    public init(localID: String, name: String, entityKind: GraphEntityKind = .entity, scope: GraphScope = .project, canonicalClassID: String? = nil, aliases: [String] = [], summary: String = "", confidence: Double = 0.8, evidenceSpanIDs: [String] = [], metadata: [String: String] = [:]) {
        self.localID = localID
        self.name = name
        self.entityKind = entityKind
        self.scope = scope
        self.canonicalClassID = canonicalClassID
        self.aliases = aliases
        self.summary = summary
        self.confidence = confidence
        self.evidenceSpanIDs = evidenceSpanIDs
        self.metadata = metadata
    }
}

public struct GraphStructuredExtractedStatement: Codable, Sendable, Equatable, Identifiable {
    public var id: String { explicitID ?? "statement-\(subjectLocalID)-\(predicate.rawValue)-\(objectLocalID)" }
    public var explicitID: String?
    public var subjectLocalID: String
    public var predicate: GraphPredicate
    public var objectLocalID: String
    public var statementText: String
    public var confidence: Double
    public var validAt: Date?
    public var referenceTime: Date?
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]

    public init(explicitID: String? = nil, subjectLocalID: String, predicate: GraphPredicate, objectLocalID: String, statementText: String, confidence: Double = 0.8, validAt: Date? = nil, referenceTime: Date? = nil, evidenceSpanIDs: [String] = [], metadata: [String: String] = [:]) {
        self.explicitID = explicitID
        self.subjectLocalID = subjectLocalID
        self.predicate = predicate
        self.objectLocalID = objectLocalID
        self.statementText = statementText
        self.confidence = confidence
        self.validAt = validAt
        self.referenceTime = referenceTime
        self.evidenceSpanIDs = evidenceSpanIDs
        self.metadata = metadata
    }
}

public enum GraphStructuredExtractionValidationError: Error, Equatable, CustomStringConvertible {
    case emptyEntityLocalID
    case duplicateEntityLocalID(String)
    case statementReferencesUnknownSubject(statementID: String, localID: String)
    case statementReferencesUnknownObject(statementID: String, localID: String)
    case missingEvidence(statementID: String)
    case unknownEvidenceSpanID(String)

    public var description: String {
        switch self {
        case .emptyEntityLocalID:
            "emptyEntityLocalID"
        case .duplicateEntityLocalID(let localID):
            "duplicateEntityLocalID: \(localID)"
        case .statementReferencesUnknownSubject(let statementID, let localID):
            "statementReferencesUnknownSubject: \(statementID) -> \(localID)"
        case .statementReferencesUnknownObject(let statementID, let localID):
            "statementReferencesUnknownObject: \(statementID) -> \(localID)"
        case .missingEvidence(let statementID):
            "missingEvidence: \(statementID)"
        case .unknownEvidenceSpanID(let spanID):
            "unknownEvidenceSpanID: \(spanID)"
        }
    }
}

public struct GraphStructuredExtractionOutput: Codable, Sendable, Equatable {
    public var entities: [GraphStructuredExtractedEntity]
    public var statements: [GraphStructuredExtractedStatement]
    public var evidenceSpans: [GraphStructuredEvidenceSpan]
    public var warnings: [GraphStructuredExtractionWarning]
    public var confidence: Double?
    public var metadata: [String: String]

    public init(entities: [GraphStructuredExtractedEntity] = [], statements: [GraphStructuredExtractedStatement] = [], evidenceSpans: [GraphStructuredEvidenceSpan] = [], warnings: [GraphStructuredExtractionWarning] = [], confidence: Double? = nil, metadata: [String: String] = [:]) {
        self.entities = entities
        self.statements = statements
        self.evidenceSpans = evidenceSpans
        self.warnings = warnings
        self.confidence = confidence
        self.metadata = metadata
    }

    public func validate(requireStatementEvidence: Bool = true) throws {
        var entityIDs = Set<String>()
        for entity in entities {
            guard !entity.localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GraphStructuredExtractionValidationError.emptyEntityLocalID
            }
            guard entityIDs.insert(entity.localID).inserted else {
                throw GraphStructuredExtractionValidationError.duplicateEntityLocalID(entity.localID)
            }
        }

        let evidenceIDs = Set(evidenceSpans.map(\.id))
        for entity in entities {
            for spanID in entity.evidenceSpanIDs where !evidenceIDs.contains(spanID) {
                throw GraphStructuredExtractionValidationError.unknownEvidenceSpanID(spanID)
            }
        }

        for statement in statements {
            if !entityIDs.contains(statement.subjectLocalID) {
                throw GraphStructuredExtractionValidationError.statementReferencesUnknownSubject(statementID: statement.id, localID: statement.subjectLocalID)
            }
            if !entityIDs.contains(statement.objectLocalID) {
                throw GraphStructuredExtractionValidationError.statementReferencesUnknownObject(statementID: statement.id, localID: statement.objectLocalID)
            }
            if requireStatementEvidence && statement.evidenceSpanIDs.isEmpty {
                throw GraphStructuredExtractionValidationError.missingEvidence(statementID: statement.id)
            }
            for spanID in statement.evidenceSpanIDs where !evidenceIDs.contains(spanID) {
                throw GraphStructuredExtractionValidationError.unknownEvidenceSpanID(spanID)
            }
        }
    }

    public func toDraft(source: GraphExtractionSource, requireStatementEvidence: Bool = true) throws -> GraphExtractionDraft {
        try validate(requireStatementEvidence: requireStatementEvidence)
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidenceSpans.map { ($0.id, $0.text) })

        let draftEntities = entities.map { entity in
            var metadata = entity.metadata
            if !entity.evidenceSpanIDs.isEmpty {
                metadata["evidence_span_ids"] = entity.evidenceSpanIDs.joined(separator: ",")
                metadata["evidence_spans"] = entity.evidenceSpanIDs.compactMap { evidenceByID[$0] }.joined(separator: "\n---\n")
            }
            return GraphExtractedEntityDraft(
                localID: entity.localID,
                name: entity.name,
                entityKind: entity.entityKind,
                scope: entity.scope,
                canonicalClassID: entity.canonicalClassID,
                aliases: entity.aliases,
                summary: entity.summary,
                confidence: entity.confidence,
                metadata: metadata
            )
        }

        let draftStatements = statements.map { statement in
            var metadata = statement.metadata
            metadata["evidence_span_ids"] = statement.evidenceSpanIDs.joined(separator: ",")
            metadata["evidence_spans"] = statement.evidenceSpanIDs.compactMap { evidenceByID[$0] }.joined(separator: "\n---\n")
            return GraphExtractedStatementDraft(
                explicitID: statement.explicitID,
                subjectLocalID: statement.subjectLocalID,
                predicate: statement.predicate,
                objectLocalID: statement.objectLocalID,
                statementText: statement.statementText,
                confidence: statement.confidence,
                validAt: statement.validAt,
                referenceTime: statement.referenceTime,
                metadata: metadata
            )
        }

        return GraphExtractionDraft(source: source, entities: draftEntities, statements: draftStatements)
    }
}
