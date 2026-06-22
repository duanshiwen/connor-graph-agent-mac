import Foundation
import ConnorGraphCore

public struct MemoryOSProvenanceRepository: Sendable {
    public var store: SQLiteMemoryOSStore
    public init(store: SQLiteMemoryOSStore) { self.store = store }
    public func save(_ object: MemoryOSProvenanceObject) throws { try store.upsert(provenance: object) }
    public func save(_ span: MemoryOSProvenanceSpan) throws { try store.upsert(span: span) }
    public func object(id: String) throws -> MemoryOSProvenanceObject? { try store.provenanceObject(id: id) }
}

public struct MemoryOSCaptureRepository: Sendable {
    public var store: SQLiteMemoryOSStore
    public init(store: SQLiteMemoryOSStore) { self.store = store }
    public func save(_ event: MemoryOSCaptureEvent) throws { try store.upsert(captureEvent: event) }
    public func save(_ block: MemoryOSTimeBlock) throws { try store.upsert(timeBlock: block) }
    public func enqueue(_ item: MemoryOSQueueItem) throws { try store.enqueue(item) }
}

public struct MemoryOSOperationalRepository: Sendable {
    public var store: SQLiteMemoryOSStore
    public init(store: SQLiteMemoryOSStore) { self.store = store }
    public func save(_ node: MemoryOSNode) throws { try store.upsert(node: node) }
    public func save(_ statement: MemoryOSStatement) throws { try store.upsert(statement: statement) }
}

public struct MemoryOSBeliefRepository: Sendable {
    public var store: SQLiteMemoryOSStore
    public init(store: SQLiteMemoryOSStore) { self.store = store }
    public func save(_ belief: MemoryOSBelief) throws { try store.upsert(belief: belief) }
}

public struct MemoryOSEntityRepository: Sendable {
    public var store: SQLiteMemoryOSStore
    public init(store: SQLiteMemoryOSStore) { self.store = store }
    public func save(_ entity: MemoryOSEntity) throws { try store.upsert(entity: entity) }
    public func entity(id: String) throws -> MemoryOSEntity? { try store.entity(id: id) }
}
