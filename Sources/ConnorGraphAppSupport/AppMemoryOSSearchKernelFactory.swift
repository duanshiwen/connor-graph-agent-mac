import Foundation
import ConnorGraphSearch
import ConnorGraphStore

public enum AppMemoryOSSearchIndexHealthStatus: String, Codable, Sendable, Equatable {
    case healthy
    case degraded
    case rebuilding
}

public struct AppMemoryOSSearchIndexHealthReport: Codable, Sendable, Equatable {
    public var status: AppMemoryOSSearchIndexHealthStatus
    public var libraryURL: URL?
    public var indexDirectory: URL
    public var databaseURL: URL
    public var checks: [String: Bool]
    public var messages: [String]

    public init(status: AppMemoryOSSearchIndexHealthStatus, libraryURL: URL?, indexDirectory: URL, databaseURL: URL, checks: [String: Bool], messages: [String]) {
        self.status = status
        self.libraryURL = libraryURL
        self.indexDirectory = indexDirectory
        self.databaseURL = databaseURL
        self.checks = checks
        self.messages = messages
    }
}

public enum AppMemoryOSSearchKernelFactory {
    public static let connorMetaFilename = "connor-meta.json"
    public static let currentIndexSchemaVersion = 4
    public static let searchKernelVersion = "0.1.0"

    public static func makeLive(paths: AppStoragePaths, fileManager: FileManager = .default) throws -> MemoryOSSearchKernel {
        let libraryURL = try resolveLibraryURL(fileManager: fileManager)
        let indexDirectory = MemoryOSSearchKernelPaths.defaultIndexDirectory(graphDirectory: paths.graphDirectory)
        try fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let kernel = try MemoryOSSearchKernel(libraryURL: libraryURL, indexDirectory: indexDirectory)
        if needsRebuild(indexDirectory: indexDirectory, databaseURL: paths.memoryOSDatabaseURL, fileManager: fileManager) {
            let count = try kernel.rebuildFromSQLite(databaseURL: paths.memoryOSDatabaseURL)
            try writeMeta(indexDirectory: indexDirectory, databaseURL: paths.memoryOSDatabaseURL, documentCount: count)
        }
        return kernel
    }

    public static func healthReport(paths: AppStoragePaths, fileManager: FileManager = .default) -> AppMemoryOSSearchIndexHealthReport {
        let indexDirectory = MemoryOSSearchKernelPaths.defaultIndexDirectory(graphDirectory: paths.graphDirectory)
        var checks: [String: Bool] = [:]
        var messages: [String] = []
        let libraryURL = try? resolveLibraryURL(fileManager: fileManager)
        checks["library_exists"] = libraryURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        checks["database_exists"] = fileManager.fileExists(atPath: paths.memoryOSDatabaseURL.path)
        checks["index_directory_exists"] = fileManager.fileExists(atPath: indexDirectory.path)
        checks["connor_meta_exists"] = fileManager.fileExists(atPath: indexDirectory.appendingPathComponent(connorMetaFilename).path)
        checks["index_schema_current"] = isSchemaCurrent(indexDirectory: indexDirectory, fileManager: fileManager)
        checks["source_database_current"] = isSourceDatabaseFingerprintCurrent(indexDirectory: indexDirectory, databaseURL: paths.memoryOSDatabaseURL, fileManager: fileManager)
        for key in checks.keys.sorted() where checks[key] != true { messages.append("\(key)=false") }
        return AppMemoryOSSearchIndexHealthReport(
            status: checks.values.allSatisfy { $0 } ? .healthy : .degraded,
            libraryURL: libraryURL,
            indexDirectory: indexDirectory,
            databaseURL: paths.memoryOSDatabaseURL,
            checks: checks,
            messages: messages
        )
    }

    public static func resolveLibraryURL(fileManager: FileManager = .default, bundle: Bundle = .main) throws -> URL {
        for candidate in candidateLibraryURLs(fileManager: fileManager, bundle: bundle) where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw MemoryOSSearchKernelError.libraryNotFound(candidateLibraryURLs(fileManager: fileManager, bundle: bundle).last ?? URL(fileURLWithPath: "libconnor_memory_search_kernel.dylib"))
    }

    public static func candidateLibraryURLs(fileManager: FileManager = .default, bundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CONNOR_MEMORY_SEARCH_KERNEL_DYLIB"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let privateFrameworksURL = bundle.privateFrameworksURL {
            candidates.append(privateFrameworksURL.appendingPathComponent("libconnor_memory_search_kernel.dylib"))
        }
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("SearchKernel", isDirectory: true).appendingPathComponent("libconnor_memory_search_kernel.dylib"))
        }
        if let executableURL = bundle.executableURL {
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent("libconnor_memory_search_kernel.dylib"))
        }
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SearchKernel", isDirectory: true)
            .appendingPathComponent("target", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("libconnor_memory_search_kernel.dylib"))
        return candidates.removingDuplicatesByPath()
    }

    private static func needsRebuild(indexDirectory: URL, databaseURL: URL, fileManager: FileManager) -> Bool {
        !isSchemaCurrent(indexDirectory: indexDirectory, fileManager: fileManager)
            || !isSourceDatabaseFingerprintCurrent(indexDirectory: indexDirectory, databaseURL: databaseURL, fileManager: fileManager)
    }

    private static func isSchemaCurrent(indexDirectory: URL, fileManager: FileManager) -> Bool {
        guard let object = readMetaObject(indexDirectory: indexDirectory, fileManager: fileManager),
              let version = object["indexSchemaVersion"] as? Int
        else { return false }
        return version == currentIndexSchemaVersion
    }

    private static func isSourceDatabaseFingerprintCurrent(indexDirectory: URL, databaseURL: URL, fileManager: FileManager) -> Bool {
        guard let object = readMetaObject(indexDirectory: indexDirectory, fileManager: fileManager),
              let indexed = object["sourceDatabaseFingerprint"] as? [String: Any]
        else { return false }
        let current = sourceDatabaseFingerprint(databaseURL: databaseURL, fileManager: fileManager)
        return comparableFingerprint(indexed) == comparableFingerprint(current)
    }

    private static func readMetaObject(indexDirectory: URL, fileManager: FileManager) -> [String: Any]? {
        let metaURL = indexDirectory.appendingPathComponent(connorMetaFilename)
        guard fileManager.fileExists(atPath: metaURL.path),
              let data = try? Data(contentsOf: metaURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func comparableFingerprint(_ object: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for key in ["databaseFileSize", "walFileSize"] {
            if let value = object[key] { result[key] = String(describing: value) }
        }
        if let counts = object["tableCounts"] as? [String: Any] {
            for key in counts.keys.sorted() {
                if let value = counts[key] { result["tableCounts.\(key)"] = String(describing: value) }
            }
        }
        return result
    }

    public static func writeMeta(indexDirectory: URL, databaseURL: URL, documentCount: Int, builtAt: Date = Date()) throws {
        let meta: [String: Any] = [
            "indexSchemaVersion": currentIndexSchemaVersion,
            "searchKernelVersion": searchKernelVersion,
            "sourceDatabasePath": databaseURL.path,
            "indexedLayers": ["L0", "L1", "L2", "L3", "L4"],
            "documentCount": documentCount,
            "builtAt": ISO8601DateFormatter().string(from: builtAt),
            "sourceDatabaseFingerprint": sourceDatabaseFingerprint(databaseURL: databaseURL)
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: indexDirectory.appendingPathComponent(connorMetaFilename), options: [.atomic])
    }

    public static func sourceDatabaseFingerprint(databaseURL: URL, fileManager: FileManager = .default) -> [String: Any] {
        var result: [String: Any] = [
            "databaseFileSize": fileSize(databaseURL, fileManager: fileManager),
            "databaseModifiedAt": fileModifiedAt(databaseURL, fileManager: fileManager) ?? "",
            "walFileSize": fileSize(URL(fileURLWithPath: databaseURL.path + "-wal"), fileManager: fileManager),
            "walModifiedAt": fileModifiedAt(URL(fileURLWithPath: databaseURL.path + "-wal"), fileManager: fileManager) ?? "",
            "shmFileSize": fileSize(URL(fileURLWithPath: databaseURL.path + "-shm"), fileManager: fileManager),
            "shmModifiedAt": fileModifiedAt(URL(fileURLWithPath: databaseURL.path + "-shm"), fileManager: fileManager) ?? ""
        ]
        if let counts = try? sourceTableCounts(databaseURL: databaseURL) {
            result["tableCounts"] = counts
        }
        return result
    }

    private static func sourceTableCounts(databaseURL: URL) throws -> [String: Int] {
        let store = try SQLiteMemoryOSStore(path: databaseURL.path)
        let tables = [
            "memory_l0_provenance_objects",
            "memory_l1_capture_events",
            "memory_l2_statements",
            "memory_l3_beliefs",
            "memory_l4_entities",
            "memory_l4_entity_statements"
        ]
        var counts: [String: Int] = [:]
        for table in tables {
            counts[table] = Int(try store.query(sql: "SELECT COUNT(*) FROM \(table);").first?.first ?? "0") ?? 0
        }
        return counts
    }

    private static func fileSize(_ url: URL, fileManager: FileManager) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func fileModifiedAt(_ url: URL, fileManager: FileManager) -> String? {
        guard let date = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }
}

private extension Array where Element == URL {
    func removingDuplicatesByPath() -> [URL] {
        var seen: Set<String> = []
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
