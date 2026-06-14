import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func markdownTextExtractorExtractsMarkdownContent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("notes.md")
    try "# Notes\nHello".write(to: file, atomically: true, encoding: .utf8)

    let result = try AttachmentTextExtraction.extract(fileURL: file, kind: .markdown, maxBytes: 1_000)

    #expect(result.status == .extracted)
    #expect(result.markdown?.contains("Hello") == true)
    #expect(result.previewText == "# Notes\nHello")
}

@Test func textExtractorSkipsOversizeFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("large.txt")
    try "0123456789".write(to: file, atomically: true, encoding: .utf8)

    let result = try AttachmentTextExtraction.extract(fileURL: file, kind: .text, maxBytes: 5)

    #expect(result.status == .skippedOversize)
    #expect(result.markdown == nil)
}

@Test func textExtractorRejectsUnsupportedBinaryKind() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("image.png")
    try Data([0, 1, 2, 3]).write(to: file)

    let result = try AttachmentTextExtraction.extract(fileURL: file, kind: .image, maxBytes: 1_000)

    #expect(result.status == .unsupported)
    #expect(result.markdown == nil)
}
