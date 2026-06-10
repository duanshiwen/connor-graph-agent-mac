import Foundation

public enum MemoryDistillationCandidateKind: String, Codable, Sendable, CaseIterable, Hashable {
    case episode
    case profileFact = "profile_fact"
    case decision
    case projectFact = "project_fact"
    case preference
    case unresolvedQuestion = "unresolved_question"
    case riskFlag = "risk_flag"
}

public enum MemoryDistillationCandidateStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case proposed
    case discarded
    case accepted
    case held
}

public struct MemoryDistillationSourceRef: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var bundleID: String
    public var messageIDs: [String]
    public var artifactIDs: [String]
    public var quote: String
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        bundleID: String,
        messageIDs: [String] = [],
        artifactIDs: [String] = [],
        quote: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.bundleID = bundleID
        self.messageIDs = messageIDs
        self.artifactIDs = artifactIDs
        self.quote = quote
        self.metadata = metadata
    }
}

public struct MemoryDistillationCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var kind: MemoryDistillationCandidateKind
    public var title: String
    public var content: String
    public var rationale: String
    public var importance: Double
    public var confidence: Double
    public var sourceRefIDs: [String]
    public var status: MemoryDistillationCandidateStatus
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: MemoryDistillationCandidateKind,
        title: String = "",
        content: String,
        rationale: String = "",
        importance: Double = 0.5,
        confidence: Double = 0.5,
        sourceRefIDs: [String] = [],
        status: MemoryDistillationCandidateStatus = .proposed,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.rationale = rationale
        self.importance = importance
        self.confidence = confidence
        self.sourceRefIDs = sourceRefIDs
        self.status = status
        self.metadata = metadata
    }
}

public struct MemoryDistillationDiscardedItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var bundleID: String
    public var reason: String
    public var summary: String

    public init(
        id: String = UUID().uuidString,
        bundleID: String,
        reason: String,
        summary: String = ""
    ) {
        self.id = id
        self.bundleID = bundleID
        self.reason = reason
        self.summary = summary
    }
}

public struct MemoryDistillationTrace: Codable, Sendable, Equatable {
    public var model: String
    public var promptVersion: String
    public var inputBundleCount: Int
    public var inputTokenEstimate: Int
    public var outputTokenEstimate: Int
    public var triggerReasons: [MemoryStagingTriggerReason]
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        model: String = "",
        promptVersion: String = "",
        inputBundleCount: Int = 0,
        inputTokenEstimate: Int = 0,
        outputTokenEstimate: Int = 0,
        triggerReasons: [MemoryStagingTriggerReason] = [],
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.model = model
        self.promptVersion = promptVersion
        self.inputBundleCount = inputBundleCount
        self.inputTokenEstimate = inputTokenEstimate
        self.outputTokenEstimate = outputTokenEstimate
        self.triggerReasons = triggerReasons
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct MemoryDistillationResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var sessionID: String
    public var sourceBufferID: String
    public var episodeCandidates: [MemoryDistillationCandidate]
    public var profileFactCandidates: [MemoryDistillationCandidate]
    public var decisionCandidates: [MemoryDistillationCandidate]
    public var projectFactCandidates: [MemoryDistillationCandidate]
    public var preferenceCandidates: [MemoryDistillationCandidate]
    public var discardedItems: [MemoryDistillationDiscardedItem]
    public var unresolvedQuestions: [MemoryDistillationCandidate]
    public var riskFlags: [MemoryDistillationCandidate]
    public var sourceRefs: [MemoryDistillationSourceRef]
    public var trace: MemoryDistillationTrace
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        sourceBufferID: String,
        episodeCandidates: [MemoryDistillationCandidate] = [],
        profileFactCandidates: [MemoryDistillationCandidate] = [],
        decisionCandidates: [MemoryDistillationCandidate] = [],
        projectFactCandidates: [MemoryDistillationCandidate] = [],
        preferenceCandidates: [MemoryDistillationCandidate] = [],
        discardedItems: [MemoryDistillationDiscardedItem] = [],
        unresolvedQuestions: [MemoryDistillationCandidate] = [],
        riskFlags: [MemoryDistillationCandidate] = [],
        sourceRefs: [MemoryDistillationSourceRef] = [],
        trace: MemoryDistillationTrace = MemoryDistillationTrace(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sourceBufferID = sourceBufferID
        self.episodeCandidates = episodeCandidates
        self.profileFactCandidates = profileFactCandidates
        self.decisionCandidates = decisionCandidates
        self.projectFactCandidates = projectFactCandidates
        self.preferenceCandidates = preferenceCandidates
        self.discardedItems = discardedItems
        self.unresolvedQuestions = unresolvedQuestions
        self.riskFlags = riskFlags
        self.sourceRefs = sourceRefs
        self.trace = trace
        self.createdAt = createdAt
    }

    public var proposedCandidates: [MemoryDistillationCandidate] {
        episodeCandidates
            + profileFactCandidates
            + decisionCandidates
            + projectFactCandidates
            + preferenceCandidates
            + unresolvedQuestions
            + riskFlags
    }

    public func candidates(kind: MemoryDistillationCandidateKind) -> [MemoryDistillationCandidate] {
        proposedCandidates.filter { $0.kind == kind }
    }
}
