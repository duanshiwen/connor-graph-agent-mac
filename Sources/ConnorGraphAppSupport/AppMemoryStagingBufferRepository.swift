import Foundation
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryStagingBufferRepository: Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func loadBuffer(sessionID: String) throws -> MemoryStagingBuffer? {
        try store.memoryStagingBuffer(sessionID: sessionID)
    }

    public func loadBuffer(id: String) throws -> MemoryStagingBuffer? {
        try store.memoryStagingBuffer(id: id)
    }

    public func loadBuffers(status: MemoryStagingBufferStatus? = nil, limit: Int = 100) throws -> [MemoryStagingBuffer] {
        try store.memoryStagingBuffers(status: status, limit: limit)
    }

    @discardableResult
    public func saveBuffer(_ buffer: MemoryStagingBuffer, updatedAt: Date = Date()) throws -> MemoryStagingBuffer {
        try store.upsertMemoryStagingBuffer(buffer, updatedAt: updatedAt)
        return buffer
    }

    public func deleteBuffer(sessionID: String) throws {
        try store.deleteMemoryStagingBuffer(sessionID: sessionID)
    }

    public func deleteBuffer(id: String) throws {
        try store.deleteMemoryStagingBuffer(id: id)
    }
}
