import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Obsidian vault import adapter")
struct ObsidianVaultNoteImportAdapterTests {
    @Test("Resolves aliases, anchors, embeds, and reports unresolved links")
    func resolvesVaultSyntax() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("People"), withIntermediateDirectories: true)
        try "---\naliases: [Robert, Bob]\n---\n# Robert\n^bio".write(to: root.appendingPathComponent("People/Robert.md"), atomically: true, encoding: .utf8)
        try Data("image".utf8).write(to: root.appendingPathComponent("portrait.png"))
        try "# Home\n[[Robert#^bio|Profile]]\n![[portrait.png]]\n[[Missing]]".write(to: root.appendingPathComponent("Home.md"), atomically: true, encoding: .utf8)
        let request = NoteImportScanRequest(sourceID: "vault", sourceURL: root, kind: .obsidianVault, options: .init())
        var notes: [ImportedNote] = []; for try await note in ObsidianVaultNoteImportAdapter().scan(request) { notes.append(note) }
        let home = try #require(notes.first { $0.title == "Home" })
        #expect(home.links.contains { $0.rawTarget == "Robert#^bio|Profile" && $0.resolvedSourceIdentity != nil && $0.metadata["anchor"] == "^bio" })
        #expect(home.links.contains { $0.rawTarget == "Missing" && $0.kind == .unresolved })
        #expect(home.attachments.first?.displayName == "portrait.png")
        let robert = try #require(notes.first { $0.title == "Robert" }); #expect(robert.sourceMetadata["obsidian_aliases"] == "Robert|Bob")
    }

    @Test("Preserves cyclic note embeds as links without recursive expansion")
    func preservesCycles() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try "# A\n![[B]]".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "# B\n![[A]]".write(to: root.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        var notes: [ImportedNote] = []; for try await note in ObsidianVaultNoteImportAdapter().scan(.init(sourceID: "v", sourceURL: root, kind: .obsidianVault, options: .init())) { notes.append(note) }
        #expect(notes.count == 2); #expect(notes.allSatisfy { $0.links.count == 1 && $0.links[0].metadata["embed"] == "true" })
    }

    private func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
}
