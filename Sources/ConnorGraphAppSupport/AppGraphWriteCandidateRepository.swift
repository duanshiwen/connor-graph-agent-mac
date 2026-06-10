import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphWriteCandidateRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var committer: GraphWriteCandidateCommitService
    public var validator: GraphWriteCandidateValidator

    public init(
        store: SQLiteGraphKernelStore,
        committer: GraphWriteCandidateCommitService = GraphWriteCandidateCommitService(),
        validator: GraphWriteCandidateValidator = GraphWriteCandidateValidator()
    ) {
        self.store = store
        self.committer = committer
        self.validator = validator
    }

    public func loadCandidates(status: GraphWriteCandidateStatus? = nil, limit: Int = 100) throws -> [GraphWriteCandidate] {
        try store.writeCandidates(groupID: "default", status: status, limit: limit)
    }
    public func loadAuditTimeline(for candidate: GraphWriteCandidate) throws -> [GraphWriteCandidateAuditPresentation] { [] }
    public func loadAuditTimelines(for candidates: [GraphWriteCandidate]) throws -> [String: [GraphWriteCandidateAuditPresentation]] { [:] }

    public func approve(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidate {
        var copy = candidate
        copy.status = .approved
        copy.updatedAt = Date()
        return copy
    }

    public func approveGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        try approve(candidate)
    }

    public func reject(_ candidate: GraphWriteCandidate, reason: String? = nil) throws -> GraphWriteCandidate {
        var copy = candidate
        copy.status = .rejected
        copy.updatedAt = Date()
        if let reason { copy.validationErrors.append(reason) }
        return copy
    }

    public func rejectGoverned(_ candidate: GraphWriteCandidate, reason: String? = nil, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        try reject(candidate, reason: reason)
    }

    public func commit(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidateCommitResult {
        try committer.commit(candidate, store: store)
    }

    public func validateGoverned(_ candidate: GraphWriteCandidate, actor: String = "agent-runtime") async throws -> (candidate: GraphWriteCandidate, validation: GraphWriteCandidateValidationResult) {
        let validation = validator.validate(candidate, store: store)
        var copy = candidate
        copy.validationErrors = validation.errors
        copy.updatedAt = Date()
        return (copy, validation)
    }

    public func commitGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidateCommitResult {
        try commit(candidate)
    }
}

public enum GraphWriteCandidateAuditSeverity: String, Sendable, Equatable {
    case info
    case warning
    case error
    case success
}

public struct GraphWriteCandidateAuditPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var actor: String
    public var severity: GraphWriteCandidateAuditSeverity
    public var createdAt: Date

    public init(id: String, title: String, detail: String, actor: String, severity: GraphWriteCandidateAuditSeverity, createdAt: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actor = actor
        self.severity = severity
        self.createdAt = createdAt
    }
}

public struct GraphWriteCandidateCommitResult: Sendable, Equatable {
    public var candidateID: String
    public var createdEntityIDs: [String]
    public var createdStatementIDs: [String]
    public var updatedStatementIDs: [String]
    public var attachedEvidenceStatementIDs: [String]

    public init(
        candidateID: String,
        createdEntityIDs: [String] = [],
        createdStatementIDs: [String] = [],
        updatedStatementIDs: [String] = [],
        attachedEvidenceStatementIDs: [String] = []
    ) {
        self.candidateID = candidateID
        self.createdEntityIDs = createdEntityIDs
        self.createdStatementIDs = createdStatementIDs
        self.updatedStatementIDs = updatedStatementIDs
        self.attachedEvidenceStatementIDs = attachedEvidenceStatementIDs
    }
}

public struct GraphWriteCandidateValidationResult: Sendable, Equatable {
    public var errors: [String]
    public var warnings: [String]
    public var isValid: Bool { errors.isEmpty }

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public struct GraphWriteCandidateValidator: Sendable {
    public init() {}

    public func validate(_ candidate: GraphWriteCandidate, store: SQLiteGraphKernelStore) -> GraphWriteCandidateValidationResult {
        GraphWriteCandidateValidationResult(warnings: ["Reviewed candidate flow is deprecated in V3; optimistic extraction/write pipeline should be used."])
    }
}

public struct GraphWriteCandidateCommitService: Sendable {
    public init() {}

    public func commit(_ candidate: GraphWriteCandidate, store: SQLiteGraphKernelStore) throws -> GraphWriteCandidateCommitResult {
        throw GraphWriteCandidateCommitError.unsupportedCandidateKind(candidate.kind)
    }
}

public enum GraphWriteCandidateCommitError: Error, Sendable, Equatable, CustomStringConvertible {
    case notApproved(String)
    case permissionDenied(String)
    case validationFailed([String])
    case unsupportedCandidateKind(GraphWriteCandidateKind)
    case missingEntity(String)
    case missingStatement(String)

    public var description: String {
        switch self {
        case .notApproved(let id): return "Candidate must be approved before commit: \(id)"
        case .permissionDenied(let reason): return "Permission denied for graph write commit: \(reason)"
        case .validationFailed(let errors): return "Graph write candidate validation failed: \(errors.joined(separator: "; "))"
        case .unsupportedCandidateKind(let kind): return "Reviewed graph write candidate flow is deprecated in V3: \(kind.rawValue)"
        case .missingEntity(let id): return "Missing graph entity: \(id)"
        case .missingStatement(let id): return "Missing graph statement: \(id)"
        }
    }
}
