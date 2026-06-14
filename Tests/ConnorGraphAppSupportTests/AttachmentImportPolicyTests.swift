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
            ("image.png", .unsupportedImage),
            ("photo.jpg", .unsupportedImage),
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

    @Test func rejectsMissingAndUnknownExtensions() {
        let missing = AttachmentImportPolicy().validate(url: URL(fileURLWithPath: "/tmp/README"))
        #expect(missing == .rejected(.missingFileExtension))
        let unknown = AttachmentImportPolicy.rejectionReason(forExtension: "weird")
        #expect(unknown == .unsupportedUnknownExtension("weird"))
    }
}
