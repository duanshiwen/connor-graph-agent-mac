import Foundation

public enum SQLiteGraphStoreError: Error, Equatable, CustomStringConvertible {
    case legacyStoreRemoved(String)

    public var description: String {
        switch self {
        case .legacyStoreRemoved(let message): "legacyStoreRemoved: \(message)"
        }
    }
}

@available(*, deprecated, message: "SQLiteGraphStore was removed during V3 cutover. Use SQLiteGraphKernelStore.")
public final class SQLiteGraphStore: @unchecked Sendable {
    public let path: String

    public init(path: String) throws {
        self.path = path
        throw SQLiteGraphStoreError.legacyStoreRemoved("SQLiteGraphStore is a removed V2 graph store. Use SQLiteGraphKernelStore.")
    }

    public func migrate() throws {
        throw SQLiteGraphStoreError.legacyStoreRemoved("SQLiteGraphStore.migrate() is unavailable. Use SQLiteGraphKernelStore.migrate().")
    }
}
