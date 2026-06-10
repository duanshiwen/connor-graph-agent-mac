import Foundation

public enum GraphEntityKind: String, Codable, Sendable, CaseIterable, Equatable {
    case entity
    case classNode = "class"
    case concept
    case timeExpression = "time_expression"
    case event
    case place
    case metric
    case document
    case artifact
    case personObject = "person_object"
    case lifeObject = "life_object"
    case workObject = "work_object"
    case communicationObject = "communication_object"
    case calendarObject = "calendar_object"
}

public enum GraphScope: String, Codable, Sendable, CaseIterable, Equatable {
    case publicScope = "public"
    case personal
    case project
    case session
    case organization
}

public enum GraphEntityStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case draft
    case archived
    case superseded
    case dismissed
    case invalidated
}

public enum GraphEdgeKind: String, Codable, Sendable, CaseIterable, Equatable {
    case taxonomy
    case structural
    case temporal
    case evidential
    case preference
    case communication
    case calendar
    case task
}

public enum GraphBeliefStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case superseded
    case contradicted
    case decayed
    case anomaly
    case inferred
    case dismissed
}

public enum GraphJustificationType: String, Codable, Sendable, CaseIterable, Equatable {
    case extracted
    case externalGrounded = "external_grounded"
    case inferred
    case userStated = "user_stated"
    case constraintDerived = "constraint_derived"
}

public struct GraphJustification: Codable, Sendable, Equatable {
    public var type: GraphJustificationType
    public var source: String
    public var strength: Double
    public var evidenceSpan: String?

    public init(type: GraphJustificationType, source: String, strength: Double, evidenceSpan: String? = nil) {
        self.type = type
        self.source = source
        self.strength = strength
        self.evidenceSpan = evidenceSpan
    }
}

public enum GraphPredicate: String, Codable, Sendable, CaseIterable, Equatable {
    case subclassOf = "SUBCLASS_OF"
    case instanceOf = "INSTANCE_OF"
    case aliasOf = "ALIAS_OF"
    case sameAs = "SAME_AS"

    case partOf = "PART_OF"
    case hasPart = "HAS_PART"
    case dependsOn = "DEPENDS_ON"
    case relatedTo = "RELATED_TO"

    case createdBy = "CREATED_BY"
    case developedBy = "DEVELOPED_BY"
    case ownedBy = "OWNED_BY"
    case locatedIn = "LOCATED_IN"
    case occurredAt = "OCCURRED_AT"
    case scheduledAt = "SCHEDULED_AT"
    case startsAt = "STARTS_AT"
    case endsAt = "ENDS_AT"

    case prefers = "PREFERS"
    case dislikes = "DISLIKES"
    case hasHabit = "HAS_HABIT"
    case hasGoal = "HAS_GOAL"
    case committedTo = "COMMITTED_TO"
    case responsibleFor = "RESPONSIBLE_FOR"
    case remindedAt = "REMINDED_AT"
    case livesAt = "LIVES_AT"
    case knowsPerson = "KNOWS_PERSON"
    case familyOf = "FAMILY_OF"

    case sentBy = "SENT_BY"
    case sentTo = "SENT_TO"
    case ccTo = "CC_TO"
    case receivedAt = "RECEIVED_AT"
    case about = "ABOUT"
    case mentions = "MENTIONS"
    case requestsAction = "REQUESTS_ACTION"
    case repliesTo = "REPLIES_TO"

    case attends = "ATTENDS"
    case organizerOf = "ORGANIZER_OF"
    case conflictsWith = "CONFLICTS_WITH"
    case blocksTime = "BLOCKS_TIME"
    case dueAt = "DUE_AT"
    case assignedTo = "ASSIGNED_TO"
    case completedAt = "COMPLETED_AT"
    case postponedTo = "POSTPONED_TO"

    case answers = "ANSWERS"
    case answeredBy = "ANSWERED_BY"
    case derivedFrom = "DERIVED_FROM"
    case supportedBy = "SUPPORTED_BY"
    case implements = "IMPLEMENTS"
    case appliesTo = "APPLIES_TO"
    case decidedBy = "DECIDED_BY"
    case supersedes = "SUPERSEDES"
}

public extension GraphPredicate {
    var edgeKind: GraphEdgeKind {
        switch self {
        case .subclassOf, .instanceOf:
            return .taxonomy
        case .aliasOf, .sameAs, .partOf, .hasPart, .dependsOn, .relatedTo:
            return .structural
        case .createdBy, .developedBy, .ownedBy, .locatedIn, .occurredAt, .startsAt, .endsAt, .livesAt:
            return .temporal
        case .scheduledAt, .remindedAt, .receivedAt, .attends, .organizerOf, .conflictsWith, .blocksTime, .dueAt, .completedAt, .postponedTo:
            return .calendar
        case .prefers, .dislikes, .hasHabit, .hasGoal:
            return .preference
        case .sentBy, .sentTo, .ccTo, .about, .mentions, .requestsAction, .repliesTo:
            return .communication
        case .committedTo, .responsibleFor, .assignedTo:
            return .task
        case .knowsPerson, .familyOf, .answers, .answeredBy, .derivedFrom, .supportedBy, .implements, .appliesTo, .decidedBy, .supersedes:
            return .evidential
        }
    }

    var isTransitive: Bool {
        switch self {
        case .subclassOf, .partOf, .dependsOn:
            return true
        default:
            return false
        }
    }

    var isSymmetric: Bool {
        switch self {
        case .sameAs, .conflictsWith, .familyOf:
            return true
        default:
            return false
        }
    }

    var inverse: GraphPredicate? {
        switch self {
        case .partOf: return .hasPart
        case .hasPart: return .partOf
        case .answers: return .answeredBy
        case .answeredBy: return .answers
        case .sentBy: return .sentTo
        case .sentTo: return .sentBy
        case .supersedes: return nil
        default: return nil
        }
    }
}

public struct GraphStableKeyBuilder {
    public static func stableKey(scope: GraphScope, entityKind: GraphEntityKind, name: String) -> String {
        "\(scope.rawValue):\(entityKind.rawValue):\(normalized(name))"
    }

    public static func normalized(_ value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        var output = ""
        var previousWasSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || isCJKUnifiedIdeograph(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("_")
                previousWasSeparator = true
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func isCJKUnifiedIdeograph(_ scalar: UnicodeScalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
    }
}

public struct GraphEntity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var name: String
    public var stableKey: String
    public var entityKind: GraphEntityKind
    public var scope: GraphScope
    public var canonicalClassID: String?
    public var aliases: [String]
    public var summary: String
    public var confidence: Double
    public var status: GraphEntityStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var validFrom: Date?
    public var validUntil: Date?
    public var supersededByEntityID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        name: String,
        stableKey: String? = nil,
        entityKind: GraphEntityKind,
        scope: GraphScope,
        canonicalClassID: String? = nil,
        aliases: [String] = [],
        summary: String = "",
        confidence: Double = 1.0,
        status: GraphEntityStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        supersededByEntityID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.name = name
        self.stableKey = stableKey ?? GraphStableKeyBuilder.stableKey(scope: scope, entityKind: entityKind, name: name)
        self.entityKind = entityKind
        self.scope = scope
        self.canonicalClassID = canonicalClassID
        self.aliases = aliases
        self.summary = summary
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.supersededByEntityID = supersededByEntityID
        self.metadata = metadata
    }
}

public struct GraphStatement: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var subjectEntityID: String
    public var predicate: GraphPredicate
    public var objectEntityID: String
    public var statementText: String
    public var edgeKind: GraphEdgeKind
    public var validAt: Date
    public var invalidAt: Date?
    public var committedAt: Date
    public var referenceTime: Date?
    public var confidence: Double
    public var beliefStatus: GraphBeliefStatus
    public var justifications: [GraphJustification]
    public var sourceEpisodeIDs: [String]
    public var invalidatedByStatementID: String?
    public var supersedesStatementIDs: [String]
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        subjectEntityID: String,
        predicate: GraphPredicate,
        objectEntityID: String,
        statementText: String,
        edgeKind: GraphEdgeKind? = nil,
        validAt: Date,
        invalidAt: Date? = nil,
        committedAt: Date = Date(),
        referenceTime: Date? = nil,
        confidence: Double = 1.0,
        beliefStatus: GraphBeliefStatus = .active,
        justifications: [GraphJustification] = [],
        sourceEpisodeIDs: [String] = [],
        invalidatedByStatementID: String? = nil,
        supersedesStatementIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.subjectEntityID = subjectEntityID
        self.predicate = predicate
        self.objectEntityID = objectEntityID
        self.statementText = statementText
        self.edgeKind = edgeKind ?? predicate.edgeKind
        self.validAt = validAt
        self.invalidAt = invalidAt
        self.committedAt = committedAt
        self.referenceTime = referenceTime
        self.confidence = confidence
        self.beliefStatus = beliefStatus
        self.justifications = justifications
        self.sourceEpisodeIDs = sourceEpisodeIDs
        self.invalidatedByStatementID = invalidatedByStatementID
        self.supersedesStatementIDs = supersedesStatementIDs
        self.metadata = metadata
    }
}

public enum GraphEpisodeV3SourceType: String, Codable, Sendable, CaseIterable, Equatable {
    case chatMessage = "chat_message"
    case observeLog = "observe_log"
    case webPage = "web_page"
    case file
    case email
    case calendar
    case manual
    case system
}

public struct GraphEpisodeV3: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var sourceType: GraphEpisodeV3SourceType
    public var sourceID: String?
    public var title: String
    public var content: String
    public var sourceDescription: String
    public var occurredAt: Date
    public var ingestedAt: Date
    public var sessionID: String?
    public var workObjectID: String?
    public var status: GraphEntityStatus
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        sourceType: GraphEpisodeV3SourceType,
        sourceID: String? = nil,
        title: String,
        content: String,
        sourceDescription: String,
        occurredAt: Date = Date(),
        ingestedAt: Date = Date(),
        sessionID: String? = nil,
        workObjectID: String? = nil,
        status: GraphEntityStatus = .active,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.title = title
        self.content = content
        self.sourceDescription = sourceDescription
        self.occurredAt = occurredAt
        self.ingestedAt = ingestedAt
        self.sessionID = sessionID
        self.workObjectID = workObjectID
        self.status = status
        self.metadata = metadata
    }
}

public enum GraphOntologyClassLifecycleStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case proposed
    case candidate
    case promoted
    case curated
}

public struct GraphOntologyClass: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var classEntityID: String
    public var classID: String
    public var displayName: String
    public var layer: Int
    public var domain: String
    public var lifecycleStatus: GraphOntologyClassLifecycleStatus
    public var description: String
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        classEntityID: String,
        classID: String,
        displayName: String,
        layer: Int,
        domain: String,
        lifecycleStatus: GraphOntologyClassLifecycleStatus = .curated,
        description: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.classEntityID = classEntityID
        self.classID = classID
        self.displayName = displayName
        self.layer = layer
        self.domain = domain
        self.lifecycleStatus = lifecycleStatus
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.metadata = metadata
    }
}
