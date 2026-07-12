import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Commercial note import stress and faults", .serialized)
struct NoteImportCommercialStressTests {
    @Test("Scans ten thousand markdown files without losing items", .timeLimit(.minutes(2)))
    func scansTenThousand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let body = Data("# Note\nContent".utf8)
        for folder in 0..<100 { let directory = root.appendingPathComponent("folder-\(folder)"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); for file in 0..<100 { try body.write(to: directory.appendingPathComponent("note-\(file).md")) } }
        var count = 0; for try await _ in MarkdownFolderNoteImportAdapter().scan(.init(sourceID: "stress", sourceURL: root, kind: .markdownFolder, options: .init())) { count += 1 }
        #expect(count == 10_000)
    }

    @Test("Processes one thousand queued operations with peak concurrency three", .timeLimit(.minutes(1)))
    func thousandQueue() async {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 3, pageSize: 32))
        let results = await scheduler.run(elements: Array(0..<1_000)) { $0 * 2 }
        #expect(results.count == 1_000); #expect(await scheduler.peakConcurrency() == 3)
    }

    @Test("Fault policy blocks traversal before backend writes")
    func blocksTraversal() throws {
        struct Backend: SafeArchiveBackend { func entries(in archive: URL) throws -> [SafeArchiveEntry] { [.init(path: "../../escape", uncompressedSize: 1, compressedSize: 1)] }; func extract(archive: URL, to destination: URL) throws { Issue.record("Extraction must not run") } }
        #expect(throws: SafeArchiveError.unsafePath("../../escape")) { _ = try SafeArchiveExtractor(backend: Backend()).extract(URL(fileURLWithPath: "/bad.zip"), to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    }
}
