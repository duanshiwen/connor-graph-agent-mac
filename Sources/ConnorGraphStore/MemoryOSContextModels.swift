import Foundation

public enum MemoryOSTaskIntent: String, Codable, Sendable, Equatable, CaseIterable {
    case answerQuestion
    case continueConversation
    case updateProject
    case debugCode
    case planWork
    case summarizeMemory
    case verifyClaim
    case resolveEntity
    case listInstances
    case explainRelationship
    case currentUserPersonalization
    case auto
}

public enum MemoryOSContextOutputMode: String, Codable, Sendable, Equatable, CaseIterable {
    case compact
    case balanced
    case evidenceHeavy
    case graphHeavy
}

public enum MemoryOSContextRole: String, Codable, Sendable, Equatable, CaseIterable {
    case currentUserProfile
    case projectState
    case operationalFact
    case reusableKnowledge
    case stableEntity
    case relation
    case evidence
    case conflict
    case uncertainty
    case historicalContext
    case nextStepHint
}

public enum MemoryOSUncertaintyLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case low
    case medium
    case high
}

public enum MemoryOSDiagnosticSeverity: String, Codable, Sendable, Equatable, CaseIterable {
    case info
    case warning
    case error
}

public enum MemoryOSDiagnosticKind: String, Codable, Sendable, Equatable, CaseIterable {
    case noRelevantMemory
    case weakEvidence
    case conflictingFacts
    case staleMemory
    case ambiguousEntity
    case budgetTruncated
    case expansionSkipped
    case provenanceUnavailable
    case lowConfidence
    case possibleDuplicate
}

public enum MemoryOSContextLanguage: String, Codable, Sendable, Equatable, CaseIterable {
    case zhHans
    case en
    case bilingual
}

public struct MemoryOSContextBudget: Sendable, Codable, Equatable {
    public var maxContextCharacters: Int
    public var maxBlocks: Int
    public var maxEntityCards: Int
    public var maxRelationCards: Int
    public var maxEvidenceCards: Int
    public var maxEvidenceRefsPerBlock: Int

    public init(
        maxContextCharacters: Int,
        maxBlocks: Int,
        maxEntityCards: Int,
        maxRelationCards: Int,
        maxEvidenceCards: Int,
        maxEvidenceRefsPerBlock: Int
    ) {
        self.maxContextCharacters = maxContextCharacters
        self.maxBlocks = maxBlocks
        self.maxEntityCards = maxEntityCards
        self.maxRelationCards = maxRelationCards
        self.maxEvidenceCards = maxEvidenceCards
        self.maxEvidenceRefsPerBlock = maxEvidenceRefsPerBlock
    }

    public static let commercialDefault = MemoryOSContextBudget(
        maxContextCharacters: 8_000,
        maxBlocks: 16,
        maxEntityCards: 10,
        maxRelationCards: 24,
        maxEvidenceCards: 8,
        maxEvidenceRefsPerBlock: 3
    )
}

public struct MemoryOSRetrievalPolicy: Sendable, Codable, Equatable {
    public var maxInitialHits: Int
    public var includeLexical: Bool
    public var includeSemantic: Bool
    public var includeGraph: Bool
    public var includeTemporalCurrentView: Bool
    public var preferCurrentFacts: Bool
    public var includeHistoricalFacts: Bool
    public var includeContradictions: Bool
    public var minScore: Double?

    public init(
        maxInitialHits: Int = 20,
        includeLexical: Bool = true,
        includeSemantic: Bool = true,
        includeGraph: Bool = true,
        includeTemporalCurrentView: Bool = true,
        preferCurrentFacts: Bool = true,
        includeHistoricalFacts: Bool = true,
        includeContradictions: Bool = true,
        minScore: Double? = nil
    ) {
        self.maxInitialHits = maxInitialHits
        self.includeLexical = includeLexical
        self.includeSemantic = includeSemantic
        self.includeGraph = includeGraph
        self.includeTemporalCurrentView = includeTemporalCurrentView
        self.preferCurrentFacts = preferCurrentFacts
        self.includeHistoricalFacts = includeHistoricalFacts
        self.includeContradictions = includeContradictions
        self.minScore = minScore
    }
}

public struct MemoryOSEvidencePolicy: Sendable, Codable, Equatable {
    public var required: Bool
    public var maxEvidenceItems: Int
    public var includeProvenanceSnippets: Bool
    public var includeRawWhenShort: Bool
    public var evidenceQualityThreshold: Double?
    public var exposeMissingEvidenceDiagnostics: Bool

    public init(
        required: Bool = false,
        maxEvidenceItems: Int = 8,
        includeProvenanceSnippets: Bool = true,
        includeRawWhenShort: Bool = true,
        evidenceQualityThreshold: Double? = nil,
        exposeMissingEvidenceDiagnostics: Bool = true
    ) {
        self.required = required
        self.maxEvidenceItems = maxEvidenceItems
        self.includeProvenanceSnippets = includeProvenanceSnippets
        self.includeRawWhenShort = includeRawWhenShort
        self.evidenceQualityThreshold = evidenceQualityThreshold
        self.exposeMissingEvidenceDiagnostics = exposeMissingEvidenceDiagnostics
    }
}

public enum MemoryOSGraphExpansionStrategy: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case entityNeighborhood
    case evidenceNeighborhood
    case classMembership
    case relationPath
    case mixed
}

public struct MemoryOSGraphExpansionPolicy: Sendable, Codable, Equatable {
    public var enabled: Bool
    public var maxDepth: Int
    public var maxEdgesPerSeed: Int
    public var allowedPredicates: [String]
    public var blockedPredicates: [String]
    public var direction: MemoryOSGraphDirection
    public var expansionStrategy: MemoryOSGraphExpansionStrategy

    public init(
        enabled: Bool = true,
        maxDepth: Int = 1,
        maxEdgesPerSeed: Int = 8,
        allowedPredicates: [String] = [],
        blockedPredicates: [String] = [],
        direction: MemoryOSGraphDirection = .both,
        expansionStrategy: MemoryOSGraphExpansionStrategy = .mixed
    ) {
        self.enabled = enabled
        self.maxDepth = max(0, maxDepth)
        self.maxEdgesPerSeed = max(0, maxEdgesPerSeed)
        self.allowedPredicates = allowedPredicates
        self.blockedPredicates = blockedPredicates
        self.direction = direction
        self.expansionStrategy = expansionStrategy
    }
}

public struct MemoryOSContextRequest: Sendable, Codable, Equatable {
    public var query: String
    public var taskIntent: MemoryOSTaskIntent
    public var subjectHints: [String]
    public var layers: [MemoryOSRetrievalLayer]
    public var retrievalPolicy: MemoryOSRetrievalPolicy
    public var evidencePolicy: MemoryOSEvidencePolicy
    public var graphPolicy: MemoryOSGraphExpansionPolicy
    public var budget: MemoryOSContextBudget
    public var outputMode: MemoryOSContextOutputMode
    public var referenceTime: Date
    public var language: MemoryOSContextLanguage

    public init(
        query: String,
        taskIntent: MemoryOSTaskIntent = .auto,
        subjectHints: [String] = [],
        layers: [MemoryOSRetrievalLayer] = MemoryOSRetrievalLayer.allCases,
        retrievalPolicy: MemoryOSRetrievalPolicy = MemoryOSRetrievalPolicy(),
        evidencePolicy: MemoryOSEvidencePolicy = MemoryOSEvidencePolicy(),
        graphPolicy: MemoryOSGraphExpansionPolicy = MemoryOSGraphExpansionPolicy(),
        budget: MemoryOSContextBudget = .commercialDefault,
        outputMode: MemoryOSContextOutputMode = .balanced,
        referenceTime: Date = Date(),
        language: MemoryOSContextLanguage = .zhHans
    ) {
        self.query = query
        self.taskIntent = taskIntent
        self.subjectHints = subjectHints
        self.layers = layers
        self.retrievalPolicy = retrievalPolicy
        self.evidencePolicy = evidencePolicy
        self.graphPolicy = graphPolicy
        self.budget = budget
        self.outputMode = outputMode
        self.referenceTime = referenceTime
        self.language = language
    }
}

public enum MemoryOSContextJSONValue: Sendable, Codable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([MemoryOSContextJSONValue])
    case object([String: MemoryOSContextJSONValue])
    case null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: MemoryOSContextJSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, MemoryOSContextJSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [MemoryOSContextJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

public struct MemoryOSAttributeSentence: Sendable, Codable, Equatable {
    public var text: String
    public var recordIDs: [String]
    public var evidenceRefs: [String]

    public init(text: String, recordIDs: [String] = [], evidenceRefs: [String] = []) {
        self.text = text
        self.recordIDs = recordIDs
        self.evidenceRefs = evidenceRefs
    }
}

public struct MemoryOSContextBlock: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var role: MemoryOSContextRole
    public var layer: MemoryOSRetrievalLayer?
    public var priority: Int
    public var text: String
    public var recordIDs: [String]
    public var entityIDs: [String]
    public var relationIDs: [String]
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var confidence: Double?
    public var validAt: Date?
    public var uncertainty: MemoryOSUncertaintyLevel

    public init(id: String, role: MemoryOSContextRole, layer: MemoryOSRetrievalLayer? = nil, priority: Int, text: String, recordIDs: [String] = [], entityIDs: [String] = [], relationIDs: [String] = [], evidenceRefs: [String] = [], provenanceRefs: [String] = [], confidence: Double? = nil, validAt: Date? = nil, uncertainty: MemoryOSUncertaintyLevel = .none) {
        self.id = id
        self.role = role
        self.layer = layer
        self.priority = priority
        self.text = text
        self.recordIDs = recordIDs
        self.entityIDs = entityIDs
        self.relationIDs = relationIDs
        self.evidenceRefs = evidenceRefs
        self.provenanceRefs = provenanceRefs
        self.confidence = confidence
        self.validAt = validAt
        self.uncertainty = uncertainty
    }
}

public struct MemoryOSEntityContextCard: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var name: String
    public var kind: String
    public var summary: String
    public var aliases: [String]
    public var attributes: [MemoryOSAttributeSentence]
    public var outgoingRelations: [String]
    public var incomingRelations: [String]
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var sourceRecordIDs: [String]

    public init(id: String, entityID: String, name: String, kind: String, summary: String, aliases: [String] = [], attributes: [MemoryOSAttributeSentence] = [], outgoingRelations: [String] = [], incomingRelations: [String] = [], evidenceRefs: [String] = [], provenanceRefs: [String] = [], sourceRecordIDs: [String] = []) {
        self.id = id
        self.entityID = entityID
        self.name = name
        self.kind = kind
        self.summary = summary
        self.aliases = aliases
        self.attributes = attributes
        self.outgoingRelations = outgoingRelations
        self.incomingRelations = incomingRelations
        self.evidenceRefs = evidenceRefs
        self.provenanceRefs = provenanceRefs
        self.sourceRecordIDs = sourceRecordIDs
    }
}

public struct MemoryOSRelationContextCard: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var sourceName: String?
    public var predicate: String
    public var predicateLabel: String
    public var targetID: String?
    public var targetName: String?
    public var sentence: String
    public var confidence: Double?
    public var validAt: Date?
    public var invalidAt: Date?
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]

    public init(id: String, sourceID: String, sourceName: String? = nil, predicate: String, predicateLabel: String, targetID: String? = nil, targetName: String? = nil, sentence: String, confidence: Double? = nil, validAt: Date? = nil, invalidAt: Date? = nil, evidenceRefs: [String] = [], provenanceRefs: [String] = []) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.predicate = predicate
        self.predicateLabel = predicateLabel
        self.targetID = targetID
        self.targetName = targetName
        self.sentence = sentence
        self.confidence = confidence
        self.validAt = validAt
        self.invalidAt = invalidAt
        self.evidenceRefs = evidenceRefs
        self.provenanceRefs = provenanceRefs
    }
}

public struct MemoryOSEvidenceContextCard: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var evidenceRef: String
    public var provenanceRef: String?
    public var snippet: String
    public var sourceTitle: String?
    public var quality: Double?

    public init(id: String, evidenceRef: String, provenanceRef: String? = nil, snippet: String, sourceTitle: String? = nil, quality: Double? = nil) {
        self.id = id
        self.evidenceRef = evidenceRef
        self.provenanceRef = provenanceRef
        self.snippet = snippet
        self.sourceTitle = sourceTitle
        self.quality = quality
    }
}

public struct MemoryOSContextDiagnostic: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var severity: MemoryOSDiagnosticSeverity
    public var kind: MemoryOSDiagnosticKind
    public var message: String
    public var affectedRecordIDs: [String]
    public var suggestedAction: String?

    public init(id: String, severity: MemoryOSDiagnosticSeverity, kind: MemoryOSDiagnosticKind, message: String, affectedRecordIDs: [String] = [], suggestedAction: String? = nil) {
        self.id = id
        self.severity = severity
        self.kind = kind
        self.message = message
        self.affectedRecordIDs = affectedRecordIDs
        self.suggestedAction = suggestedAction
    }
}

public struct MemoryOSRawRetrievalTrace: Sendable, Codable, Equatable {
    public var initialHitCount: Int
    public var expandedRelationCount: Int
    public var tracedEvidenceCount: Int
    public var retrievalMethods: [String]

    public init(initialHitCount: Int = 0, expandedRelationCount: Int = 0, tracedEvidenceCount: Int = 0, retrievalMethods: [String] = []) {
        self.initialHitCount = initialHitCount
        self.expandedRelationCount = expandedRelationCount
        self.tracedEvidenceCount = tracedEvidenceCount
        self.retrievalMethods = retrievalMethods
    }
}

public struct MemoryOSContextNextAction: Sendable, Codable, Equatable {
    public var toolName: String
    public var reason: String
    public var arguments: [String: MemoryOSContextJSONValue]

    public init(toolName: String, reason: String, arguments: [String: MemoryOSContextJSONValue] = [:]) {
        self.toolName = toolName
        self.reason = reason
        self.arguments = arguments
    }
}

public struct MemoryOSContextBudgetReport: Sendable, Codable, Equatable {
    public var maxContextCharacters: Int
    public var actualContextCharacters: Int
    public var truncatedBlockCount: Int
    public var truncatedRelationCount: Int

    public init(maxContextCharacters: Int, actualContextCharacters: Int, truncatedBlockCount: Int = 0, truncatedRelationCount: Int = 0) {
        self.maxContextCharacters = maxContextCharacters
        self.actualContextCharacters = actualContextCharacters
        self.truncatedBlockCount = truncatedBlockCount
        self.truncatedRelationCount = truncatedRelationCount
    }
}

public struct MemoryOSContextQualitySignals: Sendable, Codable, Equatable {
    public var relevanceScore: Double
    public var evidenceCoverage: Double
    public var relationCoverage: Double
    public var redundancyRate: Double
    public var staleLeakRate: Double
    public var conflictSurfacingRate: Double
    public var budgetCompliance: Double

    public init(relevanceScore: Double = 0, evidenceCoverage: Double = 0, relationCoverage: Double = 0, redundancyRate: Double = 0, staleLeakRate: Double = 0, conflictSurfacingRate: Double = 0, budgetCompliance: Double = 1) {
        self.relevanceScore = relevanceScore
        self.evidenceCoverage = evidenceCoverage
        self.relationCoverage = relationCoverage
        self.redundancyRate = redundancyRate
        self.staleLeakRate = staleLeakRate
        self.conflictSurfacingRate = conflictSurfacingRate
        self.budgetCompliance = budgetCompliance
    }
}

public struct MemoryOSContextPackage: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var query: String
    public var taskIntent: MemoryOSTaskIntent
    public var generatedAt: Date
    public var referenceTime: Date
    public var executiveSummary: String
    public var contextText: String
    public var blocks: [MemoryOSContextBlock]
    public var entities: [MemoryOSEntityContextCard]
    public var relations: [MemoryOSRelationContextCard]
    public var evidence: [MemoryOSEvidenceContextCard]
    public var diagnostics: [MemoryOSContextDiagnostic]
    public var rawRetrieval: MemoryOSRawRetrievalTrace
    public var suggestedNextActions: [MemoryOSContextNextAction]
    public var budgetReport: MemoryOSContextBudgetReport
    public var qualitySignals: MemoryOSContextQualitySignals

    public init(id: String, query: String, taskIntent: MemoryOSTaskIntent, generatedAt: Date, referenceTime: Date, executiveSummary: String, contextText: String, blocks: [MemoryOSContextBlock] = [], entities: [MemoryOSEntityContextCard] = [], relations: [MemoryOSRelationContextCard] = [], evidence: [MemoryOSEvidenceContextCard] = [], diagnostics: [MemoryOSContextDiagnostic] = [], rawRetrieval: MemoryOSRawRetrievalTrace = MemoryOSRawRetrievalTrace(), suggestedNextActions: [MemoryOSContextNextAction] = [], budgetReport: MemoryOSContextBudgetReport, qualitySignals: MemoryOSContextQualitySignals = MemoryOSContextQualitySignals()) {
        self.id = id
        self.query = query
        self.taskIntent = taskIntent
        self.generatedAt = generatedAt
        self.referenceTime = referenceTime
        self.executiveSummary = executiveSummary
        self.contextText = contextText
        self.blocks = blocks
        self.entities = entities
        self.relations = relations
        self.evidence = evidence
        self.diagnostics = diagnostics
        self.rawRetrieval = rawRetrieval
        self.suggestedNextActions = suggestedNextActions
        self.budgetReport = budgetReport
        self.qualitySignals = qualitySignals
    }
}
