import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private struct FakeBookmarkCodec: NoteImportBookmarkCoding {
    var url: URL
    var stale = false
    func createBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) { (url, stale) }
}

@Suite("Note import source access")
struct NoteImportSourceAccessServiceTests {
    @Test("Persists bookmark metadata and restores an authorized source")
    func authorizeAndRestore() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = NoteImportSourceAccessService(codec: FakeBookmarkCodec(url: root))
        let source = try service.authorize(url: root, source: .init(id: "source", kind: .obsidianVault, displayName: "Vault"))
        #expect(source.locationBookmark != nil)
        #expect(source.metadata["authorized_path"] == root.path)
        let lease = try service.access(source: source)
        #expect(try lease.validate(root.appendingPathComponent("note.md")).path.hasSuffix("note.md"))
        lease.release(); lease.release()
    }

    @Test("Rejects stale bookmarks")
    func rejectsStale() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = NoteImportSourceAccessService(codec: FakeBookmarkCodec(url: root, stale: true))
        let source = NoteImportSourceRecord(kind: .notionExport, displayName: "Notion", locationBookmark: Data([1]))
        #expect(throws: NoteImportSourceAccessError.staleBookmark) { _ = try service.access(source: source) }
    }

    @Test("Rejects paths escaping the authorized root")
    func rejectsEscape() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try directory(); defer { try? FileManager.default.removeItem(at: outside) }
        let service = NoteImportSourceAccessService(codec: FakeBookmarkCodec(url: root))
        let source = NoteImportSourceRecord(kind: .markdownFolder, displayName: "Notes", locationBookmark: Data([1]))
        let lease = try service.access(source: source)
        #expect(throws: NoteImportSourceAccessError.pathEscapesAuthorizedRoot) { _ = try lease.validate(outside.appendingPathComponent("secret.md")) }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
