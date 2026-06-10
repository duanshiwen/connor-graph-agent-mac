import Foundation
import ConnorGraphStore

public struct AppGraphAdmissionHoldQueuePresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var status: GraphAdmissionHoldQueueStatus
    public var reasons: [GraphWriteAdmissionReason]
    public var recommendedActions: [GraphAdmissionHoldRecommendedAction]
    public var createdAt: Date

    public init(item: GraphAdmissionHoldQueueItem) {
        self.id = item.id
        self.status = item.status
        self.reasons = item.reasons
        self.recommendedActions = item.recommendedActions
        self.createdAt = item.createdAt
        self.title = "\(item.status.rawValue) · \(item.sourceType.rawValue) · \(item.sourceID)"
        let reasonsText = item.reasons.map(\.rawValue).joined(separator: ", ")
        let actionsText = item.recommendedActions.map(\.rawValue).joined(separator: ", ")
        self.detail = "trace: \(item.traceID) · job: \(item.jobID) · reasons: \(reasonsText.isEmpty ? "none" : reasonsText) · actions: \(actionsText.isEmpty ? "none" : actionsText) · \(item.message)"
    }
}

public struct AppGraphAdmissionHoldQueueRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var graphID: String

    public init(store: SQLiteGraphKernelStore, graphID: String = "default") {
        self.store = store
        self.graphID = graphID
    }

    public func loadOpenItems(limit: Int = 100) throws -> [AppGraphAdmissionHoldQueuePresentation] {
        try store.admissionHoldQueueItems(graphID: graphID, status: .open, limit: limit)
            .map(AppGraphAdmissionHoldQueuePresentation.init(item:))
    }
}
