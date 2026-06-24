import Foundation

public enum FoundationKGBuiltinBootstrapper {
    public static let resourceDirectoryName = "FoundationKG"
    public static let builtinDatabaseFileName = "FoundationKG-Builtin-L4.sqlite"

    public static func builtinDatabaseURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "FoundationKG/\(builtinDatabaseFileName)", withExtension: nil)
            ?? bundle.url(forResource: "FoundationKG-Builtin-L4", withExtension: "sqlite", subdirectory: resourceDirectoryName)
    }

    public static func ensureBuiltinDatabaseIfNeeded(memoryOSDatabaseURL: URL, builtinDatabaseURL: URL, fileManager: FileManager = .default) throws -> Bool {
        if fileManager.fileExists(atPath: memoryOSDatabaseURL.path) { return false }
        try fileManager.createDirectory(at: memoryOSDatabaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copySQLiteDatabase(from: builtinDatabaseURL, to: memoryOSDatabaseURL, fileManager: fileManager)
        return true
    }

    public static func resetToBuiltinDatabase(memoryOSDatabaseURL: URL, builtinDatabaseURL: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: memoryOSDatabaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try removeSQLiteDatabase(at: memoryOSDatabaseURL, fileManager: fileManager)
        try copySQLiteDatabase(from: builtinDatabaseURL, to: memoryOSDatabaseURL, fileManager: fileManager)
    }

    private static func copySQLiteDatabase(from source: URL, to destination: URL, fileManager: FileManager) throws {
        try fileManager.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] {
            let sidecarSource = URL(fileURLWithPath: source.path + suffix)
            guard fileManager.fileExists(atPath: sidecarSource.path) else { continue }
            let sidecarDestination = URL(fileURLWithPath: destination.path + suffix)
            try fileManager.copyItem(at: sidecarSource, to: sidecarDestination)
        }
    }

    private static func removeSQLiteDatabase(at url: URL, fileManager: FileManager) throws {
        for candidate in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            if fileManager.fileExists(atPath: candidate.path) { try fileManager.removeItem(at: candidate) }
        }
    }
}
