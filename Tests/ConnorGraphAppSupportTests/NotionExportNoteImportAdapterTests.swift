import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Notion export import adapter")
struct NotionExportNoteImportAdapterTests {
    @Test("Imports markdown page IDs and local resources")
    func markdownAndResources() async throws { let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }; let id = String(repeating: "a", count: 32); try Data("image".utf8).write(to: root.appendingPathComponent("image.png")); try "# Page\n![Image](image.png)".write(to: root.appendingPathComponent("Page \(id).md"), atomically: true, encoding: .utf8); let notes = try await collect(NotionExportNoteImportAdapter(), root: root); #expect(notes.count == 1); #expect(notes[0].externalID == id); #expect(notes[0].title == "Page"); #expect(notes[0].attachments.first?.displayName == "image.png") }
    @Test("Sanitizes HTML without executing script")
    func html() async throws { let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }; try "<h1>Hello</h1><script>steal()</script><p>Body &amp; text</p>".write(to: root.appendingPathComponent("Page.html"), atomically: true, encoding: .utf8); let notes = try await collect(NotionExportNoteImportAdapter(), root: root); #expect(notes[0].markdownContent.contains("Hello")); #expect(notes[0].markdownContent.contains("Body & text")); #expect(!notes[0].markdownContent.contains("steal")) }
    @Test("Imports quoted multiline CSV rows as notes")
    func csvRows() async throws { let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }; try "Name,Description\nOne,\"Line 1\nLine 2\"\nTwo,Simple".write(to: root.appendingPathComponent("Database.csv"), atomically: true, encoding: .utf8); let notes = try await collect(NotionExportNoteImportAdapter(databaseStrategy: .rowAsNote), root: root); #expect(notes.count == 2); #expect(notes[0].markdownContent.contains("Line 1\nLine 2")); #expect(notes[1].title == "Two") }

    @Test("Imports a database summary by default")
    func defaultDatabaseSummary() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try "Name,Status\nOne,Done\nTwo,Open".write(to: root.appendingPathComponent("Database.csv"), atomically: true, encoding: .utf8)

        let note = try #require(try await collect(NotionExportNoteImportAdapter(), root: root).first)

        #expect(note.title == "Database")
        #expect(note.markdownContent.contains("数据库导出，共 2 行"))
        #expect(note.markdownContent.contains("| Name | Status |"))
        #expect(note.sourceMetadata["notion_format"] == "csv")
    }

    @Test("Imports HTML resources once and reports missing, unsafe, and symlink targets")
    func htmlResourcesAreSafe() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("image".utf8).write(to: root.appendingPathComponent("my image.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: outside)
        try """
        <h1>Page</h1>
        <img src="my%20image.png"><a href="my%20image.png">duplicate</a>
        <img src="missing.png"><img src="../outside.png"><img src="linked.png">
        """.write(to: root.appendingPathComponent("Page.html"), atomically: true, encoding: .utf8)

        let note = try #require(try await collect(NotionExportNoteImportAdapter(), root: root).first)

        #expect(note.attachments.map(\.displayName) == ["my image.png"])
        #expect(note.diagnostics.contains { $0.code == .attachmentMissing && $0.message.contains("missing.png") })
        #expect(note.diagnostics.contains { $0.code == .unsafePath && $0.message.contains("outside.png") })
        #expect(note.diagnostics.contains { $0.code == .unsafePath && $0.message.contains("linked.png") })
    }
    private func collect(_ adapter: NotionExportNoteImportAdapter, root: URL) async throws -> [ImportedNote] { var notes: [ImportedNote] = []; for try await note in adapter.scan(.init(sourceID: "n", sourceURL: root, kind: .notionExport, options: .init())) { notes.append(note) }; return notes }
    private func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
}
