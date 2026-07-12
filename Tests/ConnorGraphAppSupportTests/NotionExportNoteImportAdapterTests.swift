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
    private func collect(_ adapter: NotionExportNoteImportAdapter, root: URL) async throws -> [ImportedNote] { var notes: [ImportedNote] = []; for try await note in adapter.scan(.init(sourceID: "n", sourceURL: root, kind: .notionExport, options: .init())) { notes.append(note) }; return notes }
    private func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
}
