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

    @Test("Resolves page links to internal notes, keeps Notion URLs and external URLs")
    func pageLinksResolveToInternalNotes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let parentID = String(repeating: "a", count: 32)
        let childOneID = String(repeating: "b", count: 32)
        let childTwoID = String(repeating: "c", count: 32)
        let missingID = String(repeating: "d", count: 32)
        let parent = """
        # Parent

        [Child One](Child%20One%20\(childOneID).md)
        [Child Two](https://www.notion.so/Child-Two-\(childTwoID))
        [Outside](https://example.com/outside)
        [Dead](Missing%20\(missingID).md)
        """
        try parent.write(to: root.appendingPathComponent("Parent \(parentID).md"), atomically: true, encoding: .utf8)
        try "# Child One".write(to: root.appendingPathComponent("Child One \(childOneID).md"), atomically: true, encoding: .utf8)
        try "# Child Two".write(to: root.appendingPathComponent("Child Two \(childTwoID).md"), atomically: true, encoding: .utf8)

        let notes = try await collect(NotionExportNoteImportAdapter(), root: root)
        #expect(notes.count == 3)
        let parentNote = try #require(notes.first { $0.title == "Parent" })
        let childOne = try #require(notes.first { $0.title == "Child One" })
        let childTwo = try #require(notes.first { $0.title == "Child Two" })

        let internalLinks = parentNote.links.filter { $0.kind == .internalNote }
        #expect(internalLinks.contains { $0.resolvedSourceIdentity == childOne.sourceIdentity })
        #expect(internalLinks.contains { $0.resolvedSourceIdentity == childTwo.sourceIdentity })
        #expect(parentNote.links.contains { $0.kind == .externalURL && $0.rawTarget == "https://example.com/outside" })
        #expect(parentNote.links.contains { $0.kind == .unresolved && $0.rawTarget == "Missing%20\(missingID).md" })
        #expect(parentNote.diagnostics.contains { $0.message.contains("未解析") })
        #expect(parentNote.attachments.isEmpty)
    }

    @Test("Resolves HTML page links and keeps image assets")
    func htmlPageLinksResolve() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let parentID = String(repeating: "a", count: 32)
        let childID = String(repeating: "b", count: 32)
        try Data("image".utf8).write(to: root.appendingPathComponent("pic.png"))
        try "<h1>Parent</h1><a href=\"Child%20One%20\(childID).html\">Child One</a><img src=\"pic.png\">"
            .write(to: root.appendingPathComponent("Parent \(parentID).html"), atomically: true, encoding: .utf8)
        try "<h1>Child One</h1>".write(to: root.appendingPathComponent("Child One \(childID).html"), atomically: true, encoding: .utf8)

        let notes = try await collect(NotionExportNoteImportAdapter(), root: root)
        let parentNote = try #require(notes.first { $0.title == "Parent" })
        let childNote = try #require(notes.first { $0.title == "Child One" })
        #expect(parentNote.links.contains { $0.kind == .internalNote && $0.resolvedSourceIdentity == childNote.sourceIdentity })
        #expect(parentNote.attachments.map(\.displayName) == ["pic.png"])
    }

    @Test("Imports every note in nested folders plus CSV")
    func nestedFoldersAllImported() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let idA = String(repeating: "a", count: 32)
        let idB = String(repeating: "b", count: 32)
        let idC = String(repeating: "c", count: 32)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Top/Sub"), withIntermediateDirectories: true)
        try "# Home".write(to: root.appendingPathComponent("Top/Home \(idA).md"), atomically: true, encoding: .utf8)
        try "# Deep".write(to: root.appendingPathComponent("Top/Sub/Deep \(idB).md"), atomically: true, encoding: .utf8)
        try "# Root".write(to: root.appendingPathComponent("Root \(idC).md"), atomically: true, encoding: .utf8)
        try "Name,Status\nOne,Done".write(to: root.appendingPathComponent("Database.csv"), atomically: true, encoding: .utf8)

        let notes = try await collect(NotionExportNoteImportAdapter(), root: root)
        #expect(notes.count == 4)
        #expect(notes.contains { $0.relativePath == "Top/Home \(idA).md" })
        #expect(notes.contains { $0.relativePath == "Top/Sub/Deep \(idB).md" })
        #expect(notes.contains { $0.relativePath == "Root \(idC).md" })
        #expect(notes.contains { $0.title == "Database" })
    }

    @Test("Extracts a Notion zip and imports all pages with links")
    func zipSourceResolvesAndImports() async throws {
        let sourceDir = try directory(); defer { try? FileManager.default.removeItem(at: sourceDir) }
        let idParent = String(repeating: "a", count: 32)
        let idChild = String(repeating: "b", count: 32)
        try "# Parent\n\n[Child](Child%20\(idChild).md)".write(to: sourceDir.appendingPathComponent("Parent \(idParent).md"), atomically: true, encoding: .utf8)
        try "# Child".write(to: sourceDir.appendingPathComponent("Child \(idChild).md"), atomically: true, encoding: .utf8)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        try makeZip(from: sourceDir, to: archive)

        let resolved = try NotionExportSourceResolver.extractIfZip(archive)
        defer { try? FileManager.default.removeItem(at: resolved) }
        #expect(resolved.path != archive.path)

        let entries = try SystemZipArchiveBackend().entries(in: archive)
        #expect(entries.contains { $0.path == "Parent \(idParent).md" })
        #expect(entries.contains { $0.path == "Child \(idChild).md" })

        let notes = try await collect(NotionExportNoteImportAdapter(), root: resolved)
        #expect(notes.count == 2)
        let parentNote = try #require(notes.first { $0.title == "Parent" })
        let childNote = try #require(notes.first { $0.title == "Child" })
        #expect(parentNote.links.contains { $0.kind == .internalNote && $0.resolvedSourceIdentity == childNote.sourceIdentity })
    }

    @Test("Rejects a raw zip passed directly to the adapter")
    func adapterRejectsDirectZip() async throws {
        let sourceDir = try directory(); defer { try? FileManager.default.removeItem(at: sourceDir) }
        try "# Page".write(to: sourceDir.appendingPathComponent("Page \(String(repeating: "a", count: 32)).md"), atomically: true, encoding: .utf8)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        try makeZip(from: sourceDir, to: archive)

        await #expect(throws: NoteImportErrorCode.unsupportedFormat) {
            _ = try await collect(NotionExportNoteImportAdapter(), root: archive)
        }
    }

    @Test("Preserves a clean tree hierarchy for the whole Notion export")
    func preservesTreeHierarchy() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let idA = String(repeating: "a", count: 32)
        let idB = String(repeating: "b", count: 32)
        let idC = String(repeating: "c", count: 32)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("笔记本/子分类/深层"), withIntermediateDirectories: true)
        try "# 首页".write(to: root.appendingPathComponent("笔记本/首页 \(idA).md"), atomically: true, encoding: .utf8)
        try "# 子页面".write(to: root.appendingPathComponent("笔记本/子分类/子页面 \(idB).md"), atomically: true, encoding: .utf8)
        try "# 深层页面".write(to: root.appendingPathComponent("笔记本/子分类/深层/深层页面 \(idC).md"), atomically: true, encoding: .utf8)

        let notes = try await collect(NotionExportNoteImportAdapter(), root: root, preserveHierarchy: true)

        #expect(notes.count == 3)
        #expect(try #require(notes.first { $0.title == "首页" }).hierarchy == ["笔记本"])
        #expect(try #require(notes.first { $0.title == "子页面" }).hierarchy == ["笔记本", "子分类"])
        #expect(try #require(notes.first { $0.title == "深层页面" }).hierarchy == ["笔记本", "子分类", "深层"])
        // 显式关闭层级时保持扁平
        let flat = try await collect(NotionExportNoteImportAdapter(), root: root, preserveHierarchy: false)
        #expect(flat.allSatisfy { $0.hierarchy.isEmpty })
    }

    @Test("Rebuilds parent-child hierarchy from the whole Notion tree")
    func rebuildsParentHierarchy() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let idA = String(repeating: "a", count: 32)
        let idB = String(repeating: "b", count: 32)
        let idC = String(repeating: "c", count: 32)
        // self-folder page 笔记本：导出为 笔记本 <id>/笔记本 <id>.md
        try FileManager.default.createDirectory(at: root.appendingPathComponent("笔记本 \(idA)"), withIntermediateDirectories: true)
        try "# 笔记本".write(to: root.appendingPathComponent("笔记本 \(idA)/笔记本 \(idA).md"), atomically: true, encoding: .utf8)
        // self-folder page 子分类：笔记本 <id>/子分类 <id>/子分类 <id>.md
        try FileManager.default.createDirectory(at: root.appendingPathComponent("笔记本 \(idA)/子分类 \(idB)"), withIntermediateDirectories: true)
        try "# 子分类".write(to: root.appendingPathComponent("笔记本 \(idA)/子分类 \(idB)/子分类 \(idB).md"), atomically: true, encoding: .utf8)
        // 叶子页 子页面：笔记本 <id>/子分类 <id>/子页面 <id>.md
        try "# 子页面".write(to: root.appendingPathComponent("笔记本 \(idA)/子分类 \(idB)/子页面 \(idC).md"), atomically: true, encoding: .utf8)

        let notes = try await collect(NotionExportNoteImportAdapter(), root: root, preserveHierarchy: true)

        #expect(notes.count == 3)
        let notebook = try #require(notes.first { $0.title == "笔记本" })
        let category = try #require(notes.first { $0.title == "子分类" })
        let leaf = try #require(notes.first { $0.title == "子页面" })
        #expect(notebook.hierarchy == ["笔记本"])
        #expect(category.hierarchy == ["笔记本", "子分类"])
        #expect(leaf.hierarchy == ["笔记本", "子分类"])
        // 层级重建：叶子 → 子分类 → 笔记本 → 根
        #expect(leaf.hierarchyParent == category.sourceIdentity)
        #expect(category.hierarchyParent == notebook.sourceIdentity)
        #expect(notebook.hierarchyParent == nil)
    }

    private func makeZip(from directory: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directory.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "ditto", code: Int(process.terminationStatus)) }
    }

    private func collect(_ adapter: NotionExportNoteImportAdapter, root: URL, preserveHierarchy: Bool = false) async throws -> [ImportedNote] {
        var options = NoteImportOptions()
        options.preserveHierarchy = preserveHierarchy
        var notes: [ImportedNote] = []
        for try await note in adapter.scan(.init(sourceID: "n", sourceURL: root, kind: .notionExport, options: options)) { notes.append(note) }
        return notes
    }
    private func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
}
