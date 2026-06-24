import Foundation
import ConnorGraphSearch
import ConnorGraphStore

public enum AppMemoryOSSearchKernelFactory {
    public static let connorMetaFilename = "connor-meta.json"
    public static let currentIndexSchemaVersion = 4
    public static let searchKernelVersion = "0.1.0"

    public static func makeLive(paths: AppStoragePaths, fileManager: FileManager = .default) throws -> MemoryOSSearchKernel {
        let libraryURL = try resolveLibraryURL(fileManager: fileManager)
        let indexDirectory = MemoryOSSearchKernelPaths.defaultIndexDirectory(graphDirectory: paths.graphDirectory)
        try fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let kernel = try MemoryOSSearchKernel(libraryURL: libraryURL, indexDirectory: indexDirectory)
        if needsRebuild(indexDirectory: indexDirectory, fileManager: fileManager) {
            let count = try kernel.rebuildFromSQLite(databaseURL: paths.memoryOSDatabaseURL)
            try writeMeta(indexDirectory: indexDirectory, databaseURL: paths.memoryOSDatabaseURL, documentCount: count)
        }
        return kernel
    }

    public static func resolveLibraryURL(fileManager: FileManager = .default) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CONNOR_MEMORY_SEARCH_KERNEL_DYLIB"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            guard fileManager.fileExists(atPath: url.path) else { throw MemoryOSSearchKernelError.libraryNotFound(url) }
            return url
        }
        let repositoryCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SearchKernel", isDirectory: true)
            .appendingPathComponent("target", isDirectory: true)
            .appendingPathComponent("release", isDirectory: true)
            .appendingPathComponent("libconnor_memory_search_kernel.dylib")
        guard fileManager.fileExists(atPath: repositoryCandidate.path) else {
            throw MemoryOSSearchKernelError.libraryNotFound(repositoryCandidate)
        }
        return repositoryCandidate
    }

    private static func needsRebuild(indexDirectory: URL, fileManager: FileManager) -> Bool {
        let metaURL = indexDirectory.appendingPathComponent(connorMetaFilename)
        guard fileManager.fileExists(atPath: metaURL.path),
              let data = try? Data(contentsOf: metaURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["indexSchemaVersion"] as? Int
        else { return true }
        return version != currentIndexSchemaVersion
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
