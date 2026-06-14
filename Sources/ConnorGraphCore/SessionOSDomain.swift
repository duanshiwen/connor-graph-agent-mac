import Foundation

public struct SessionOSJournalPayload: Codable, Sendable, Equatable {
    public var action: String
    public var message: String
    public var metadata: [String: String]

    public init(action: String, message: String, metadata: [String: String] = [:]) {
        self.action = action
        self.message = message
        self.metadata = metadata
    }
}

public enum SessionPendingPlanStatus: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case draft
    case waitingForApproval = "waiting_for_approval"
    case accepted
    case rejected
    case expired
}

public struct SessionPendingPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var title: String
    public var markdownPath: String?
    public var contentReference: String?
    public var status: SessionPendingPlanStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var resolvedAt: Date?
    public var resolutionReason: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        title: String,
        markdownPath: String? = nil,
        contentReference: String? = nil,
        status: SessionPendingPlanStatus = .waitingForApproval,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolutionReason: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.markdownPath = markdownPath
        self.contentReference = contentReference
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.resolutionReason = resolutionReason
    }
}

public struct SessionBranchRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceSessionID: String
    public var targetSessionID: String
    public var branchPointMessageID: String?
    public var branchPointEventID: String?
    public var reason: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sourceSessionID: String,
        targetSessionID: String,
        branchPointMessageID: String? = nil,
        branchPointEventID: String? = nil,
        reason: String = "session branch",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceSessionID = sourceSessionID
        self.targetSessionID = targetSessionID
        self.branchPointMessageID = branchPointMessageID
        self.branchPointEventID = branchPointEventID
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct SessionLLMOverride: Codable, Sendable, Equatable {
    public var providerMode: String
    public var model: String
    public var baseURLString: String?

    public init(
        providerMode: String,
        model: String,
        baseURLString: String? = nil
    ) {
        self.providerMode = providerMode
        self.model = model
        self.baseURLString = baseURLString
    }
}

public struct SessionOSRestoreSnapshot: Codable, Sendable, Equatable {
    public var sessionID: String
    public var activeRuns: [AgentRun]
    public var pendingPlans: [SessionPendingPlan]
    public var pendingApprovalCount: Int
    public var restoredAt: Date

    public init(
        sessionID: String,
        activeRuns: [AgentRun] = [],
        pendingPlans: [SessionPendingPlan] = [],
        pendingApprovalCount: Int = 0,
        restoredAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.activeRuns = activeRuns
        self.pendingPlans = pendingPlans
        self.pendingApprovalCount = pendingApprovalCount
        self.restoredAt = restoredAt
    }
}
