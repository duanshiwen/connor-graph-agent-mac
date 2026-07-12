import Foundation
import Testing
@testable import ConnorGraphAppSupport

private struct MemoryArchiveBackend: SafeArchiveBackend { var values: [SafeArchiveEntry]; func entries(in archive: URL) throws -> [SafeArchiveEntry] { values }; func extract(archive: URL, to destination: URL) throws { for entry in values where !entry.isDirectory { let url = destination.appendingPathComponent(entry.path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(repeating: 1, count: Int(min(entry.uncompressedSize, 16))).write(to: url) } } }

@Suite("Safe archive extractor")
struct SafeArchiveExtractorTests {
    @Test("Rejects zip slip and symbolic links")
    func rejectsUnsafeEntries() throws {
        let archive = URL(fileURLWithPath: "/fake.zip"), output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: SafeArchiveError.unsafePath("../secret")) { _ = try SafeArchiveExtractor(backend: MemoryArchiveBackend(values: [.init(path: "../secret", uncompressedSize: 1, compressedSize: 1)])).extract(archive, to: output) }
        #expect(throws: SafeArchiveError.symbolicLink("link")) { _ = try SafeArchiveExtractor(backend: MemoryArchiveBackend(values: [.init(path: "link", uncompressedSize: 1, compressedSize: 1, isSymbolicLink: true)])).extract(archive, to: output) }
    }
    @Test("Rejects compression bombs and total size overflow")
    func rejectsLimits() throws {
        let archive = URL(fileURLWithPath: "/fake.zip"), output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: SafeArchiveError.compressionBomb("bomb")) { _ = try SafeArchiveExtractor(backend: MemoryArchiveBackend(values: [.init(path: "bomb", uncompressedSize: 10_000, compressedSize: 1)]), limits: .init(maxCompressionRatio: 100)).extract(archive, to: output) }
        #expect(throws: SafeArchiveError.totalSizeLimit) { _ = try SafeArchiveExtractor(backend: MemoryArchiveBackend(values: [.init(path: "a", uncompressedSize: 8, compressedSize: 8), .init(path: "b", uncompressedSize: 8, compressedSize: 8)]), limits: .init(maxTotalBytes: 10)).extract(archive, to: output) }
    }
    @Test("Extracts validated entries inside a dedicated root")
    func extractsSafeEntries() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: output) }
        let entries = try SafeArchiveExtractor(backend: MemoryArchiveBackend(values: [.init(path: "Folder/Page.md", uncompressedSize: 5, compressedSize: 5)])).extract(URL(fileURLWithPath: "/fake.zip"), to: output)
        #expect(entries.count == 1); #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("Folder/Page.md").path))
    }
}
