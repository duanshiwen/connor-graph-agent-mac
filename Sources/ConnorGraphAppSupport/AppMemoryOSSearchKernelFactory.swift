import Foundation
import ConnorGraphSearch

public enum AppMemoryOSSearchKernelFactory {
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
        let metaURL = indexDirectory.appendingPathComponent("connor-meta.json")
        guard fileManager.fileExists(atPath: metaURL.path),
              let data = try? Data(contentsOf: metaURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["indexSchemaVersion"] as? Int
        else { return true }
        return version != 4
    }

    private static func writeMeta(indexDirectory: URL, databaseURL: URL, documentCount: Int) throws {
        let meta: [String: Any] = [
            "indexSchemaVersion": 4,
            "searchKernelVersion": "0.1.0",
            "sourceDatabasePath": databaseURL.path,
            "indexedLayers": ["L0", "L1", "L2", "L3", "L4"],
            "documentCount": documentCount,
            "builtAt": "2026-06-24T23:57:00+08:00"
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: indexDirectory.appendingPathComponent("connor-meta.json"), options: [.atomic])
    }
}
