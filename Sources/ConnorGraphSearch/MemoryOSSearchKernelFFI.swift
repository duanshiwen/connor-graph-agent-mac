import Foundation
import Darwin

public enum MemoryOSSearchKernelError: Error, Sendable, CustomStringConvertible {
    case libraryNotFound(URL)
    case symbolMissing(String)
    case openFailed(String)
    case queryFailed(String)
    case rebuildFailed(String)
    case upsertFailed(String)
    case deleteFailed(String)
    case drainFailed(String)
    case invalidResponse(String)

    public var description: String {
        switch self {
        case .libraryNotFound(let url): "Search kernel library not found: \(url.path)"
        case .symbolMissing(let name): "Search kernel symbol missing: \(name)"
        case .openFailed(let message): "Search kernel open failed: \(message)"
        case .queryFailed(let message): "Search kernel query failed: \(message)"
        case .rebuildFailed(let message): "Search kernel rebuild failed: \(message)"
        case .upsertFailed(let message): "Search kernel upsert failed: \(message)"
        case .deleteFailed(let message): "Search kernel delete failed: \(message)"
        case .drainFailed(let message): "Search kernel queue drain failed: \(message)"
        case .invalidResponse(let message): "Search kernel invalid response: \(message)"
        }
    }
}

final class MemoryOSSearchKernelFFI {
    typealias OpenFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> OpaquePointer?
    typealias CloseFn = @convention(c) (OpaquePointer?) -> Void
    typealias QueryFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias RebuildFromSQLiteFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias UpsertRecordFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias DeleteRecordFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias DrainQueueFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<UInt>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias FreeStringFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    let libraryHandle: UnsafeMutableRawPointer
    let open: OpenFn
    let close: CloseFn
    let query: QueryFn
    let rebuildFromSQLite: RebuildFromSQLiteFn
    let upsertRecord: UpsertRecordFn
    let deleteRecord: DeleteRecordFn
    let drainQueue: DrainQueueFn
    let freeString: FreeStringFn

    init(libraryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw MemoryOSSearchKernelError.libraryNotFound(libraryURL)
        }
        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? libraryURL.path
            throw MemoryOSSearchKernelError.openFailed(message)
        }
        self.libraryHandle = handle
        self.open = try Self.load(handle, "connor_search_open")
        self.close = try Self.load(handle, "connor_search_close")
        self.query = try Self.load(handle, "connor_search_query")
        self.rebuildFromSQLite = try Self.load(handle, "connor_search_rebuild_from_sqlite")
        self.upsertRecord = try Self.load(handle, "connor_search_upsert_record")
        self.deleteRecord = try Self.load(handle, "connor_search_delete_record")
        self.drainQueue = try Self.load(handle, "connor_search_drain_queue")
        self.freeString = try Self.load(handle, "connor_search_free_string")
    }

    deinit {
        dlclose(libraryHandle)
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw MemoryOSSearchKernelError.symbolMissing(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    func takeCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        freeString(pointer)
        return value
    }
}
