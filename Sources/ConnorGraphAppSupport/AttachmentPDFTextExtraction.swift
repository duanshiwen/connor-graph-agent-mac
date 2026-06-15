import Foundation
import PDFKit
import ConnorGraphCore

public enum AttachmentPDFTextExtraction {
    public static func extract(
        fileURL: URL,
        attachmentID: String = "",
        maxBytes: Int64 = 25_000_000
    ) throws -> AttachmentExtractionResult {
        let startedAt = Date()
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= maxBytes else {
            let report = AgentAttachmentExtractionReport(
                attachmentID: attachmentID,
                engine: .builtinPDFText,
                status: .skippedOversize,
                warnings: ["PDF exceeds built-in extraction size limit."],
                startedAt: startedAt,
                completedAt: Date()
            )
            return AttachmentExtractionResult(report: report)
        }
        guard let document = PDFDocument(url: fileURL) else {
            let report = AgentAttachmentExtractionReport(
                attachmentID: attachmentID,
                engine: .builtinPDFText,
                status: .failed,
                errors: ["Unable to open PDF document."],
                startedAt: startedAt,
                completedAt: Date()
            )
            return AttachmentExtractionResult(report: report)
        }

        var sections: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = (page.string ?? page.attributedString?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            sections.append("""
            ## Page \(index + 1)

            \(text)
            """)
        }

        guard !sections.isEmpty else {
            let report = AgentAttachmentExtractionReport(
                attachmentID: attachmentID,
                engine: .builtinPDFText,
                status: .unsupported,
                warnings: ["PDF has no selectable text. OCR or a document sidecar is required."],
                startedAt: startedAt,
                completedAt: Date()
            )
            return AttachmentExtractionResult(report: report)
        }

        let markdown = """
        # Extracted attachment: \(fileURL.lastPathComponent)

        \(sections.joined(separator: "\n\n"))
        """
        let report = AgentAttachmentExtractionReport(
            attachmentID: attachmentID,
            engine: .builtinPDFText,
            status: .extracted,
            capabilitiesUsed: ["pdf-selectable-text"],
            startedAt: startedAt,
            completedAt: Date()
        )
        return AttachmentExtractionResult(
            report: report,
            extractedMarkdown: markdown,
            previewText: preview(markdown)
        )
    }

    public static func supports(kind: AgentAttachmentKind) -> Bool {
        kind == .pdf
    }

    private static func preview(_ text: String, max: Int = 240) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }
}
