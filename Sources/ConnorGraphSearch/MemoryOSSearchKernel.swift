    import Foundation

public final class MemoryOSSearchKernel: @unchecked Sendable {
    private let ffi: MemoryOSSearchKernelFFI
    private let handle: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public let libraryURL: URL
    public let indexDirectory: URL

    public init(libraryURL: URL, indexDirectory: URL) throws {
        self.libraryURL = libraryURL
        self.indexDirectory = indexDirectory
        let loadedFFI = try MemoryOSSearchKernelFFI(libraryURL: libraryURL)
        var errorPointer: UnsafeMutablePointer<CChar>?
        let opened = indexDirectory.path.withCString { indexPath in
            loadedFFI.open(indexPath, &errorPointer)
        }
        guard let opened else {
            throw MemoryOSSearchKernelError.openFailed(loadedFFI.takeCString(errorPointer))
        }
        self.ffi = loadedFFI
        self.handle = opened
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    deinit {
        ffi.close(handle)
    }

    public func rebuildFromSQLite(databaseURL: URL, limitPerLayer: Int? = nil) throws -> Int {
        var errorPointer: UnsafeMutablePointer<CChar>?
        var indexedCount: UInt = 0
        let rawLimit = UInt(limitPerLayer ?? 0)
        let status = databaseURL.path.withCString { databasePath in
            ffi.rebuildFromSQLite(handle, databasePath, rawLimit, &indexedCount, &errorPointer)
        }
        guard status == 0 else {
            throw MemoryOSSearchKernelError.rebuildFailed(ffi.takeCString(errorPointer))
        }
        return Int(indexedCount)
    }

    /// Upserts one record into the index, or removes the stale document when the
    /// source record no longer exists. Returns whether the record was upserted.
    public func upsertRecord(databaseURL: URL, layer: String, recordID: String) throws -> Bool {
        var errorPointer: UnsafeMutablePointer<CChar>?
        var upserted: Int32 = 0
        let status = databaseURL.path.withCString { databasePath in
            layer.withCString { layerCString in
                recordID.withCString { recordIDCString in
                    ffi.upsertRecord(handle, databasePath, layerCString, recordIDCString, &upserted, &errorPointer)
                }
            }
        }
        guard status == 0 else {
            throw MemoryOSSearchKernelError.upsertFailed(ffi.takeCString(errorPointer))
        }
        return upserted != 0
    }

    /// Removes a document from the index by layer + record id.
    public func deleteRecord(layer: String, recordID: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = layer.withCString { layerCString in
            recordID.withCString { recordIDCString in
                ffi.deleteRecord(handle, layerCString, recordIDCString, &errorPointer)
            }
        }
        guard status == 0 else {
            throw MemoryOSSearchKernelError.deleteFailed(ffi.takeCString(errorPointer))
        }
    }

    /// Consumes up to `limit` pending `memory_search_index_queue` items.
    public struct DrainResult: Sendable, Equatable {
        public var upserted: Int
        public var deleted: Int
        public var failed: Int
        public var remaining: Int

        public init(upserted: Int, deleted: Int, failed: Int, remaining: Int) {
            self.upserted = upserted
            self.deleted = deleted
            self.failed = failed
            self.remaining = remaining
        }

        public var processed: Int { upserted + deleted }
        public var isComplete: Bool { failed == 0 && remaining == 0 }
    }

    public func drainQueue(databaseURL: URL, limit: Int) throws -> DrainResult {
        var errorPointer: UnsafeMutablePointer<CChar>?
        var upserted: UInt = 0
        var deleted: UInt = 0
        var failed: UInt = 0
        var remaining: UInt = 0
        let rawLimit = UInt(max(1, limit))
        let status = databaseURL.path.withCString { databasePath in
            ffi.drainQueue(handle, databasePath, rawLimit, &upserted, &deleted, &failed, &remaining, &errorPointer)
        }
        guard status == 0 else {
            throw MemoryOSSearchKernelError.drainFailed(ffi.takeCString(errorPointer))
        }
        return DrainResult(
            upserted: Int(upserted),
            deleted: Int(deleted),
            failed: Int(failed),
            remaining: Int(remaining)
        )
    }

    public func search(_ request: MemoryOSSearchKernelRequest) throws -> MemoryOSSearchKernelResponse {
        let requestData = try encoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw MemoryOSSearchKernelError.invalidResponse("request JSON is not UTF-8")
        }
        var resultPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = requestJSON.withCString { requestCString in
            ffi.query(handle, requestCString, &resultPointer, &errorPointer)
        }
        guard status == 0 else {
            throw MemoryOSSearchKernelError.queryFailed(ffi.takeCString(errorPointer))
        }
        let resultJSON = ffi.takeCString(resultPointer)
        guard let responseData = resultJSON.data(using: .utf8) else {
            throw MemoryOSSearchKernelError.invalidResponse("response JSON is not UTF-8")
        }
        do {
            return try decoder.decode(MemoryOSSearchKernelResponse.self, from: responseData)
        } catch {
            throw MemoryOSSearchKernelError.invalidResponse(error.localizedDescription + ": " + resultJSON)
        }
    }

    public static func defaultReleaseLibraryURL(repositoryRoot: URL) -> URL {
        repositoryRoot
            .appendingPathComponent("SearchKernel", isDirectory: true)
            .appendingPathComponent("target", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("libconnor_memory_search_kernel.dylib")
    }
}
