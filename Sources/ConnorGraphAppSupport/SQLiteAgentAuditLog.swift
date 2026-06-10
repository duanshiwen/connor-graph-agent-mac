import Foundation
import ConnorGraphAgent
import ConnorGraphStore

public struct SQLiteAgentAuditLog: AgentAuditLog, Sendable {
    private let store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func record(_ event: AgentAuditEvent) async {
        // Audit persistence will be reintroduced on the V3 app repository layer.
    }
}
