import Foundation

/// Durable local intent; an empty data store alone is never evidence of a user deletion.
public struct AccountSyncLocalDeletions: Sendable {
    public let directory: URL
    private static let gate = NSRecursiveLock()
    private var url: URL { directory.appendingPathComponent("local-sync-deletions.json") }
    public init(directory: URL) { self.directory = directory }
    public func pending() throws -> [String:Int64] {
        Self.gate.lock(); defer { Self.gate.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String:Int64].self, from: Data(contentsOf: url))
    }
    public func record(collection: String, id: String) throws {
        Self.gate.lock(); defer { Self.gate.unlock() }
        var entries = try pending(); entries["\(collection)|\(id)"] = Int64(Date().timeIntervalSince1970 * 1_000)
        try save(entries)
    }
    public func clear(_ key: String) throws {
        Self.gate.lock(); defer { Self.gate.unlock() }
        var entries = try pending(); guard entries.removeValue(forKey: key) != nil else { return }
        try save(entries)
    }
    private func save(_ entries: [String:Int64]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        AppAccountSyncSignal.postLocalDataDidChange()
    }
}
