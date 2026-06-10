import Foundation
import ConnorGraphAgent
import ConnorGraphStore

public struct SQLiteAgentAuditLog: AgentAuditLog, Sendable {
    private let store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func record(_ event: AgentAuditEvent) async {
        do {
            try store.append(auditEvent: event)
        } catch {
            // Audit logging is best-effort; do not propagate errors
        }
    }
}
