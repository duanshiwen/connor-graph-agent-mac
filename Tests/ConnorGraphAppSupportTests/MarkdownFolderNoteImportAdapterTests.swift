import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Markdown folder import adapter")
struct MarkdownFolderNoteImportAdapterTests {
    @Test("Recursively scans markdown and preserves hierarchy only when requested")
    func recursiveScan() async throws {
        let fixture = try Fixture()
        try fixture.write("---\ntitle: Commercial Note\ntags: import\n---\n# Ignored heading\nBody", at: "Projects/Connor/note.md")
        try fixture.write("not markdown", at: "Projects/skip.txt")
        let notes = try await fixture.scan(options: .init(preserveHierarchy: true))
        #expect(notes.count == 1)
        #expect(notes[0].title == "Commercial Note")
        #expect(notes[0].relativePath == "Projects/Connor/note.md")
        #expect(notes[0].hierarchy == ["Projects", "Connor"])
        #expect(notes[0].sourceMetadata["encoding"] == "utf-8")
    }

    @Test("Flattens nested Markdown folders by default")
    func flattenedHierarchy() async throws {
        let fixture = try Fixture()
        try fixture.write("# Nested", at: "Projects/Connor/note.md")
        let notes = try await fixture.scan()
        let note = try #require(notes.first)
        #expect(note.relativePath == "Projects/Connor/note.md")
        #expect(note.hierarchy.isEmpty)
    }

    @Test("Supports mixed UTF-8 and GB18030 files")
    func mixedEncoding() async throws {
        let fixture = try Fixture()
        try fixture.write("# UTF Note\nContent", at: "utf.md")
        let gb = TextDecodingService.encoding(named: "gb18030")!
        try fixture.writeData("# 中文旧笔记\n正文".data(using: gb)!, at: "legacy.md")
        let notes = try await fixture.scan(options: .init(defaultEncodingName: nil))
        #expect(Set(notes.map(\.title)) == ["UTF Note", "中文旧笔记"])
    }

    @Test("Skips hidden files and symbolic links")
    func skipsHiddenAndSymlinks() async throws {
        let fixture = try Fixture()
        try fixture.write("# Visible", at: "visible.md")
        try fixture.write("# Hidden", at: ".hidden/secret.md")
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("alias.md"), withDestinationURL: fixture.root.appendingPathComponent("visible.md"))
        #expect(try await fixture.scan().map(\.title) == ["Visible"])
    }

    @Test("Normalized text hash ignores BOM and line endings")
    func normalizedHash() async throws {
        let first = try Fixture(); let second = try Fixture()
        try first.writeData(Data([0xEF, 0xBB, 0xBF]) + Data("# Same\r\nBody".utf8), at: "same.md")
        try second.write("# Same\nBody", at: "same.md")
        let a = try await first.scan()[0]; let b = try await second.scan()[0]
        #expect(a.rawByteHash != b.rawByteHash)
        #expect(a.normalizedTextHash == b.normalizedTextHash)
    }

    private final class Fixture {
        let root: URL
        init() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: root) }
        func write(_ text: String, at path: String) throws { try writeData(Data(text.utf8), at: path) }
        func writeData(_ data: Data, at path: String) throws { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url) }
        func scan(options: NoteImportOptions = .init()) async throws -> [ImportedNote] {
            let request = NoteImportScanRequest(sourceID: "source", sourceURL: root, kind: .markdownFolder, options: options)
            var notes: [ImportedNote] = []
            for try await note in MarkdownFolderNoteImportAdapter().scan(request) { notes.append(note) }
            return notes
        }
    }
}
