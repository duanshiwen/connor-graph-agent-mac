import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Import Policy Tests")
struct AttachmentImportPolicyTests {
    @Test func acceptsStrictTextAttachmentAllowlist() {
        let accepted: [(String, AgentAttachmentKind)] = [
            ("notes.txt", .text),
            ("notes.md", .markdown),
            ("app.log", .text),
            ("data.json", .json),
            ("rows.csv", .csv),
            ("config.yaml", .code),
            ("schema.xml", .code),
            ("photo.png", .image),
            ("photo.jpg", .image),
            ("photo.webp", .image),
            ("photo.heic", .image),
            ("main.swift", .code),
            ("script.py", .code),
            ("style.scss", .code)
        ]
        for (filename, expectedKind) in accepted {
            #expect(AttachmentImportPolicy.acceptedKind(forExtension: URL(fileURLWithPath: filename).pathExtension) == expectedKind)
        }
    }

    @Test func rejectsUnsupportedAttachmentFamilies() {
        let rejected: [(String, AttachmentImportRejectionReason)] = [
            ("page.html", .unsupportedHTML),
            ("page.htm", .unsupportedHTML),
            ("vector.svg", .unsupportedSVG),
            ("paper.pdf", .unsupportedPDF),
            ("audio.mp3", .unsupportedAudio),
            ("video.mp4", .unsupportedVideo),
            ("doc.docx", .unsupportedOffice),
            ("sheet.xlsx", .unsupportedOffice),
            ("slides.pptx", .unsupportedOffice),
            ("draft.pages", .unsupportedIWork),
            ("archive.zip", .unsupportedArchive),
            ("archive.tar", .unsupportedArchive),
            ("db.sqlite", .unsupportedDatabase),
            ("installer.dmg", .unsupportedExecutableOrBinary)
        ]
        for (filename, expectedReason) in rejected {
            #expect(AttachmentImportPolicy.rejectionReason(forExtension: URL(fileURLWithPath: filename).pathExtension) == expectedReason)
        }
    }

    @Test func appliesSeparateImageSizeLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = root.appendingPathComponent("large.json")
        let image = root.appendingPathComponent("large.png")
        try Data(repeating: 0, count: 600_000).write(to: text)
        try Data(repeating: 0, count: 600_000).write(to: image)

        let policy = AttachmentImportPolicy(maxAcceptedBytes: 512_000, maxImageBytes: 10_000_000)

        #expect(policy.validate(url: text) == .rejected(.fileTooLarge(512_000)))
        #expect(policy.validate(url: image) == .accepted(kind: .image))
    }

    @Test func rejectsMissingAndUnknownExtensions() {
        let missing = AttachmentImportPolicy().validate(url: URL(fileURLWithPath: "/tmp/README"))
        #expect(missing == .rejected(.missingFileExtension))
        let unknown = AttachmentImportPolicy.rejectionReason(forExtension: "weird")
        #expect(unknown == .unsupportedUnknownExtension("weird"))
    }
}
