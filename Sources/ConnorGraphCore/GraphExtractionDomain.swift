import Foundation

public enum GraphExtractionSourceType: String, Codable, Sendable, CaseIterable, Equatable {
    case email
    case calendarEvent = "calendar_event"
    case note
    case chat
    case webpage
    case document
    case manual
}

public struct GraphExtractionSource: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var graphID: String
    public var sourceType: GraphExtractionSourceType
    public var title: String
    public var content: String
    public var occurredAt: Date
    public var sessionID: String?
    public var workObjectID: String?
    public var metadata: [String: String]

    public init(id: String, graphID: String, sourceType: GraphExtractionSourceType, title: String, content: String, occurredAt: Date, sessionID: String? = nil, workObjectID: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.graphID = graphID
        self.sourceType = sourceType
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.sessionID = sessionID
        self.workObjectID = workObjectID
        self.metadata = metadata
    }

    public var episodeSourceType: GraphEpisodeV3SourceType {
        switch sourceType {
        case .email: .email
        case .calendarEvent: .calendar
        case .chat: .chatMessage
        case .webpage: .webPage
        case .document: .file
        case .note, .manual: .manual
        }
    }
}

public struct GraphExtractedEntityDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: String { localID }
    public var localID: String
    public var name: String
    public var entityKind: GraphEntityKind
    public var scope: GraphScope
    public var canonicalClassID: String?
    public var aliases: [String]
    public var summary: String
    public var confidence: Double
    public var metadata: [String: String]

    public init(localID: String, name: String, entityKind: GraphEntityKind = .entity, scope: GraphScope = .project, canonicalClassID: String? = nil, aliases: [String] = [], summary: String = "", confidence: Double = 0.8, metadata: [String: String] = [:]) {
        self.localID = localID
        self.name = name
        self.entityKind = entityKind
        self.scope = scope
        self.canonicalClassID = canonicalClassID
        self.aliases = aliases
        self.summary = summary
        self.confidence = confidence
        self.metadata = metadata
    }
}

public struct GraphExtractedStatementDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: String { explicitID ?? "statement-\(subjectLocalID)-\(predicate.rawValue)-\(objectLocalID)" }
    public var explicitID: String?
    public var subjectLocalID: String
    public var predicate: GraphPredicate
    public var objectLocalID: String
    public var statementText: String
    public var confidence: Double
    public var validAt: Date?
    public var referenceTime: Date?
    public var metadata: [String: String]

    public init(explicitID: String? = nil, subjectLocalID: String, predicate: GraphPredicate, objectLocalID: String, statementText: String, confidence: Double = 0.8, validAt: Date? = nil, referenceTime: Date? = nil, metadata: [String: String] = [:]) {
        self.explicitID = explicitID
        self.subjectLocalID = subjectLocalID
        self.predicate = predicate
        self.objectLocalID = objectLocalID
        self.statementText = statementText
        self.confidence = confidence
        self.validAt = validAt
        self.referenceTime = referenceTime
        self.metadata = metadata
    }
}

public enum GraphExtractionError: Error, Equatable, CustomStringConvertible {
    case unknownEntityLocalID(String)

    public var description: String {
        switch self {
        case .unknownEntityLocalID(let localID): "unknownEntityLocalID: \(localID)"
        }
    }
}

public struct GraphExtractionDraft: Codable, Sendable, Equatable {
    public var source: GraphExtractionSource
    public var entities: [GraphExtractedEntityDraft]
    public var statements: [GraphExtractedStatementDraft]

    public init(source: GraphExtractionSource, entities: [GraphExtractedEntityDraft] = [], statements: [GraphExtractedStatementDraft] = []) {
        self.source = source
        self.entities = entities
        self.statements = statements
    }

    public func toOptimisticWriteBatch(now: Date = Date()) throws -> GraphOptimisticWriteBatch {
        let episodeID = "episode-\(source.id)"
        let episode = GraphEpisodeV3(
            id: episodeID,
            graphID: source.graphID,
            sourceType: source.episodeSourceType,
            sourceID: source.id,
            title: source.title,
            content: source.content,
            sourceDescription: source.sourceType.rawValue,
            occurredAt: source.occurredAt,
            ingestedAt: now,
            sessionID: source.sessionID,
            workObjectID: source.workObjectID,
            metadata: source.metadata
        )

        var entityByLocalID: [String: GraphEntity] = [:]
        let graphEntities = entities.map { draft in
            let entity = GraphEntity(
                id: stableID(prefix: "entity", graphID: source.graphID, localID: draft.localID),
                graphID: source.graphID,
                name: draft.name,
                entityKind: draft.entityKind,
                scope: draft.scope,
                canonicalClassID: draft.canonicalClassID,
                aliases: draft.aliases,
                summary: draft.summary,
                confidence: draft.confidence,
                createdAt: now,
                updatedAt: now,
                metadata: draft.metadata
            )
            entityByLocalID[draft.localID] = entity
            return entity
        }

        let graphStatements = try statements.map { draft in
            guard let subject = entityByLocalID[draft.subjectLocalID] else { throw GraphExtractionError.unknownEntityLocalID(draft.subjectLocalID) }
            guard let object = entityByLocalID[draft.objectLocalID] else { throw GraphExtractionError.unknownEntityLocalID(draft.objectLocalID) }
            return GraphStatement(
                id: draft.explicitID ?? stableID(prefix: "statement", graphID: source.graphID, localID: "\(draft.subjectLocalID)-\(draft.predicate.rawValue)-\(draft.objectLocalID)"),
                graphID: source.graphID,
                subjectEntityID: subject.id,
                predicate: draft.predicate,
                objectEntityID: object.id,
                statementText: draft.statementText,
                validAt: draft.validAt ?? source.occurredAt,
                committedAt: now,
                referenceTime: draft.referenceTime,
                confidence: draft.confidence,
                justifications: [GraphJustification(type: .extracted, source: episodeID, strength: draft.confidence)],
                sourceEpisodeIDs: [episodeID],
                metadata: draft.metadata
            )
        }

        return GraphOptimisticWriteBatch(graphID: source.graphID, episode: episode, entities: graphEntities, statements: graphStatements, now: now)
    }

    private func stableID(prefix: String, graphID: String, localID: String) -> String {
        let normalized = localID.lowercased().replacingOccurrences(of: " ", with: "-")
        return "\(prefix)-\(graphID)-\(normalized)"
    }
}
