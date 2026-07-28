import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Outbound Mail Attachment Resolver Tests")
struct OutboundMailAttachmentResolverTests {
    @Test func resolvesImportedAttachmentFromCurrentSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-attachment-resolver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let sourceURL = root.appendingPathComponent("brief.txt")
        let sourceData = Data("attachment body".utf8)
        try sourceData.write(to: sourceURL)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: sourceURL, sessionID: "session-a")

        let resolved = try await AppSessionOutboundMailAttachmentResolver(store: store).resolve(
            ids: [MailAttachmentID(rawValue: manifest.id)],
            sessionID: "session-a"
        )

        let attachment = try #require(resolved.first)
        #expect(resolved.count == 1)
        #expect(attachment.filename == "brief.txt")
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.data == sourceData)
        #expect(attachment.contentHash == manifest.sha256)
    }

    @Test func doesNotResolveAttachmentFromAnotherSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-attachment-isolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let sourceURL = root.appendingPathComponent("private.txt")
        try Data("private".utf8).write(to: sourceURL)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: sourceURL, sessionID: "session-a")
        let resolver = AppSessionOutboundMailAttachmentResolver(store: store)

        await #expect(throws: MailRuntimeError.attachmentNotFound(manifest.id)) {
            _ = try await resolver.resolve(
                ids: [MailAttachmentID(rawValue: manifest.id)],
                sessionID: "session-b"
            )
        }
    }
}
