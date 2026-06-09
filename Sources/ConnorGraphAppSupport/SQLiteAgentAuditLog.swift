import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct SQLiteAgentAuditLog: AgentAuditLog, Sendable {
    private let store: SQLiteGraphStore

    public init(store: SQLiteGraphStore) {
        self.store = store
    }

    public func record(_ event: AgentAuditEvent) async {
        try? store.recordSync(event)
    }
}
