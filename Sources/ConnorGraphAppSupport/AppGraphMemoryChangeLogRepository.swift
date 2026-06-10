import Foundation
import ConnorGraphStore

public struct AppGraphMemoryChangeLogPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var action: GraphMemoryChangeLogAction
    public var createdAt: Date

    public init(entry: GraphMemoryChangeLogEntry) {
        self.id = entry.id
        self.action = entry.action
        self.createdAt = entry.createdAt
        self.title = "\(entry.action.rawValue) · \(entry.sourceType?.rawValue ?? "unknown") · \(entry.sourceID ?? "unknown")"
        let entityText = entry.entityIDs.isEmpty ? "none" : entry.entityIDs.joined(separator: ", ")
        let statementText = entry.statementIDs.isEmpty ? "none" : entry.statementIDs.joined(separator: ", ")
        let anomalyText = entry.anomalyIDs.isEmpty ? "none" : entry.anomalyIDs.joined(separator: ", ")
        self.detail = "trace: \(entry.traceID ?? "none") · job: \(entry.jobID ?? "none") · entities: \(entityText) · statements: \(statementText) · anomalies: \(anomalyText) · \(entry.summary)"
    }
}

public struct AppGraphMemoryChangeLogRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var graphID: String

    public init(store: SQLiteGraphKernelStore, graphID: String = "default") {
        self.store = store
        self.graphID = graphID
    }

    public func loadRecentEntries(limit: Int = 100) throws -> [AppGraphMemoryChangeLogPresentation] {
        try store.memoryChangeLogEntries(graphID: graphID, limit: limit)
            .map(AppGraphMemoryChangeLogPresentation.init(entry:))
    }
}
