import AppKit
import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment PDF Text Extraction Tests")
struct AttachmentPDFTextExtractionTests {
    @Test func extractsSelectablePDFTextAsMarkdownWithPageHeadings() throws {
        let file = try makePDF(textByPage: ["Hello from page one", "Second page contract clause"])

        let result = try AttachmentPDFTextExtraction.extract(fileURL: file, attachmentID: "pdf-a", maxBytes: 1_000_000)

        #expect(result.report.attachmentID == "pdf-a")
        #expect(result.report.engine == .builtinPDFText)
        #expect(result.report.status == .extracted)
        #expect(result.report.capabilitiesUsed == ["pdf-selectable-text"])
        #expect(result.extractedMarkdown?.contains("# Extracted attachment:") == true)
        #expect(result.extractedMarkdown?.contains("## Page 1") == true)
        #expect(result.extractedMarkdown?.contains("Hello from page one") == true)
        #expect(result.extractedMarkdown?.contains("## Page 2") == true)
    }

    @Test func returnsUnsupportedForPDFWithoutSelectableText() throws {
        let file = try makePDF(textByPage: [""])

        let result = try AttachmentPDFTextExtraction.extract(fileURL: file, attachmentID: "scan", maxBytes: 1_000_000)

        #expect(result.report.attachmentID == "scan")
        #expect(result.report.engine == .builtinPDFText)
        #expect(result.report.status == .unsupported)
        #expect(result.report.warnings.first?.contains("no selectable text") == true)
        #expect(result.extractedMarkdown == nil)
    }

    @Test func skipsOversizePDFsForBuiltinExtraction() throws {
        let file = try makePDF(textByPage: ["Hello"])

        let result = try AttachmentPDFTextExtraction.extract(fileURL: file, attachmentID: "big", maxBytes: 1)

        #expect(result.report.status == .skippedOversize)
        #expect(result.extractedMarkdown == nil)
    }

    @Test func orchestratorUsesBuiltinPDFTextBeforeSidecars() async throws {
        let file = try makePDF(textByPage: ["Built in PDF text"])
        let request = AttachmentExtractionRequest(
            sessionID: "session",
            manifest: manifest(kind: .pdf),
            originalFileURL: file,
            derivativesDirectoryURL: file.deletingLastPathComponent()
        )
        let orchestrator = AttachmentExtractionOrchestrator(sidecars: [FakeAttachmentExtractionSidecar(markdown: "sidecar")])

        let result = try await orchestrator.extract(request)

        #expect(result.report.engine == .builtinPDFText)
        #expect(result.report.status == .extracted)
        #expect(result.extractedMarkdown?.contains("Built in PDF text") == true)
    }

    private func makePDF(textByPage: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("sample.pdf")
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw CocoaError(.fileWriteUnknown) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw CocoaError(.fileWriteUnknown) }
        for text in textByPage {
            context.beginPDFPage(nil)
            if !text.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.black
                ]
                text.draw(at: CGPoint(x: 72, y: 700), withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
            context.endPDFPage()
        }
        context.closePDF()
        try data.write(to: url, options: .atomic)
        return url
    }

    private func manifest(kind: AgentAttachmentKind) -> AgentAttachmentManifest {
        AgentAttachmentManifest(
            id: "attachment",
            displayName: "file.pdf",
            originalFilename: "file.pdf",
            normalizedFilename: "file.pdf",
            kind: kind,
            byteCount: 3,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/attachment/original/file.pdf",
            manifestRelativePath: "attachments/attachment/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
