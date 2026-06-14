import CryptoKit
import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func sessionAttachmentStoreImportsFileIntoSessionCapsule() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let source = root.appendingPathComponent("source notes.md")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "# Notes\nHello attachment".write(to: source, atomically: true, encoding: .utf8)
    let store = AppSessionAttachmentStore(paths: paths)

    let manifest = try store.importFile(at: source, sessionID: "session-1", now: Date(timeIntervalSince1970: 1_000))

    #expect(manifest.displayName == "source notes.md")
    #expect(manifest.kind == .markdown)
    #expect(manifest.extractionStatus == .extracted)
    let manifestURL = paths.sessionsDirectory
        .appendingPathComponent("session-1", isDirectory: true)
        .appendingPathComponent(manifest.manifestRelativePath)
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let originalURL = paths.sessionsDirectory
        .appendingPathComponent("session-1", isDirectory: true)
        .appendingPathComponent(manifest.storedRelativePath)
    #expect(FileManager.default.fileExists(atPath: originalURL.path))
    let extracted = try #require(manifest.extractedTextRelativePath)
    let extractedURL = paths.sessionsDirectory
        .appendingPathComponent("session-1", isDirectory: true)
        .appendingPathComponent(extracted)
    #expect(try String(contentsOf: extractedURL, encoding: .utf8).contains("Hello attachment"))
}

@Test func sessionAttachmentStoreSanitizesUnsafeFilenamesAndComputesSHA256() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let sourceDirectory = root.appendingPathComponent("input", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let source = sourceDirectory.appendingPathComponent(".. unsafe:name.txt")
    let body = "hello"
    try body.write(to: source, atomically: true, encoding: .utf8)
    let store = AppSessionAttachmentStore(paths: paths)

    let manifest = try store.importFile(at: source, sessionID: "session-1")

    #expect(!manifest.normalizedFilename.contains(".."))
    #expect(!manifest.normalizedFilename.contains(":"))
    let digest = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    #expect(manifest.sha256 == digest)
}
