import Foundation
import ConnorGraphCore

public struct SafeArchiveEntry: Sendable, Equatable { public var path: String; public var uncompressedSize: Int64; public var compressedSize: Int64; public var isDirectory: Bool; public var isSymbolicLink: Bool; public init(path: String, uncompressedSize: Int64, compressedSize: Int64, isDirectory: Bool = false, isSymbolicLink: Bool = false) { self.path = path; self.uncompressedSize = uncompressedSize; self.compressedSize = compressedSize; self.isDirectory = isDirectory; self.isSymbolicLink = isSymbolicLink } }
public protocol SafeArchiveBackend: Sendable { func entries(in archive: URL) throws -> [SafeArchiveEntry]; func extract(archive: URL, to destination: URL) throws }
public struct SafeArchiveLimits: Sendable, Equatable { public var maxEntries: Int; public var maxEntryBytes: Int64; public var maxTotalBytes: Int64; public var maxCompressionRatio: Double; public var maxDepth: Int; public init(maxEntries: Int = 100_000, maxEntryBytes: Int64 = 2_000_000_000, maxTotalBytes: Int64 = 10_000_000_000, maxCompressionRatio: Double = 1_000, maxDepth: Int = 64) { self.maxEntries = maxEntries; self.maxEntryBytes = maxEntryBytes; self.maxTotalBytes = maxTotalBytes; self.maxCompressionRatio = maxCompressionRatio; self.maxDepth = maxDepth } }
public enum SafeArchiveError: Error, Sendable, Equatable { case unsafePath(String); case symbolicLink(String); case entryLimit; case entryTooLarge(String); case totalSizeLimit; case compressionBomb(String); case depthLimit(String); case extractionEscapedRoot(String) }

public struct SafeArchiveExtractor: Sendable {
    public var backend: any SafeArchiveBackend; public var limits: SafeArchiveLimits
    public init(backend: any SafeArchiveBackend, limits: SafeArchiveLimits = .init()) { self.backend = backend; self.limits = limits }
    public func extract(_ archive: URL, to destination: URL) throws -> [SafeArchiveEntry] {
        let entries = try backend.entries(in: archive); guard entries.count <= limits.maxEntries else { throw SafeArchiveError.entryLimit }
        var total: Int64 = 0
        for entry in entries { try validate(entry); let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize); guard !overflow, sum <= limits.maxTotalBytes else { throw SafeArchiveError.totalSizeLimit }; total = sum }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true); try backend.extract(archive: archive, to: destination)
        let root = destination.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        if let e = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey]) { for case let url as URL in e { let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey]); guard values.isSymbolicLink != true else { throw SafeArchiveError.symbolicLink(url.path) }; guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else { throw SafeArchiveError.extractionEscapedRoot(url.path) } } }
        return entries
    }
    private func validate(_ entry: SafeArchiveEntry) throws { let path = entry.path.replacingOccurrences(of: "\\", with: "/"); guard !path.hasPrefix("/"), !path.contains(":/"), !path.split(separator: "/").contains("..") else { throw SafeArchiveError.unsafePath(entry.path) }; guard !entry.isSymbolicLink else { throw SafeArchiveError.symbolicLink(entry.path) }; guard entry.uncompressedSize >= 0, entry.uncompressedSize <= limits.maxEntryBytes else { throw SafeArchiveError.entryTooLarge(entry.path) }; guard path.split(separator: "/").count <= limits.maxDepth else { throw SafeArchiveError.depthLimit(entry.path) }; if entry.uncompressedSize > 0 { guard entry.compressedSize > 0, Double(entry.uncompressedSize) / Double(entry.compressedSize) <= limits.maxCompressionRatio else { throw SafeArchiveError.compressionBomb(entry.path) } } }
}
