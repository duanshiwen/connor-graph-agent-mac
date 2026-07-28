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

public enum IWorkAttachmentTextExtraction {
    private static let supportedExtensions: Set<String> = ["pages", "numbers", "keynote"]
    private static let previewPDFRelativePaths = [
        "QuickLook/Preview.pdf",
        "QuickLook/preview.pdf",
        "Preview.pdf",
        "preview.pdf"
    ]

    public static func supports(fileExtension: String?) -> Bool {
        guard let fileExtension else { return false }
        return supportedExtensions.contains(fileExtension.lowercased())
    }

    public static func extract(
        fileURL: URL,
        attachmentID: String = "",
        displayName: String? = nil,
        maxPDFBytes: Int64 = 25_000_000
    ) throws -> AttachmentExtractionResult {
        let startedAt = Date()
        guard supports(fileExtension: fileURL.pathExtension) else {
            return result(
                attachmentID: attachmentID,
                status: .unsupported,
                startedAt: startedAt,
                warnings: ["File is not an Apple iWork document."]
            )
        }

        if let text = spotlightText(for: fileURL) {
            return extractedResult(
                text: text,
                title: displayName ?? fileURL.lastPathComponent,
                attachmentID: attachmentID,
                capability: "iwork-spotlight-text",
                startedAt: startedAt
            )
        }

        if let previewURL = embeddedPreviewPDF(in: fileURL),
           let extracted = try? extractPreviewPDF(
               previewURL,
               title: displayName ?? fileURL.lastPathComponent,
               attachmentID: attachmentID,
               maxPDFBytes: maxPDFBytes,
               startedAt: startedAt,
               capability: "iwork-embedded-preview"
           ) {
            return extracted
        }

        if let text = legacyXMLText(in: fileURL) {
            return extractedResult(
                text: text,
                title: displayName ?? fileURL.lastPathComponent,
                attachmentID: attachmentID,
                capability: "iwork-legacy-xml",
                startedAt: startedAt
            )
        }

        if let generatedPreview = quickLookPreviewPDF(for: fileURL) {
            defer { try? FileManager.default.removeItem(at: generatedPreview.cleanupDirectory) }
            if let extracted = try? extractPreviewPDF(
                generatedPreview.pdfURL,
                title: displayName ?? fileURL.lastPathComponent,
                attachmentID: attachmentID,
                maxPDFBytes: maxPDFBytes,
                startedAt: startedAt,
                capability: "iwork-quicklook-preview"
            ) {
                return extracted
            }
        }

        return result(
            attachmentID: attachmentID,
            status: .unsupported,
            startedAt: startedAt,
            warnings: ["The iWork document did not expose selectable text through Spotlight, its package preview, legacy XML, or Quick Look."]
        )
    }

    private static func spotlightText(for fileURL: URL) -> String? {
        let item = NSMetadataItem(url: fileURL)
        return normalizedText(item?.value(forAttribute: NSMetadataItemTextContentKey) as? String)
    }

    private static func embeddedPreviewPDF(in fileURL: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return previewPDFRelativePaths
            .map { fileURL.appendingPathComponent($0) }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private static func legacyXMLText(in fileURL: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let candidates = ["index.xml", "index.apxl"]
            .map { fileURL.appendingPathComponent($0) }
        guard let xmlURL = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }),
              let parser = XMLParser(contentsOf: xmlURL) else {
            return nil
        }
        let collector = LegacyIWorkXMLTextCollector()
        parser.delegate = collector
        guard parser.parse() else { return nil }
        return normalizedText(collector.text)
    }

    private static func quickLookPreviewPDF(for fileURL: URL) -> (pdfURL: URL, cleanupDirectory: URL)? {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-iwork-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            process.arguments = ["-x", "-o", outputDirectory.path, "-p", fileURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(30)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            guard process.terminationStatus == 0,
                  let enumerator = FileManager.default.enumerator(
                      at: outputDirectory,
                      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                      options: [.skipsHiddenFiles]
                  ) else {
                try? FileManager.default.removeItem(at: outputDirectory)
                return nil
            }
            for case let candidate as URL in enumerator where candidate.pathExtension.lowercased() == "pdf" {
                return (candidate, outputDirectory)
            }
        } catch {
            try? FileManager.default.removeItem(at: outputDirectory)
            return nil
        }
        try? FileManager.default.removeItem(at: outputDirectory)
        return nil
    }

    private static func extractPreviewPDF(
        _ pdfURL: URL,
        title: String,
        attachmentID: String,
        maxPDFBytes: Int64,
        startedAt: Date,
        capability: String
    ) throws -> AttachmentExtractionResult? {
        let pdf = try AttachmentPDFTextExtraction.extract(
            fileURL: pdfURL,
            attachmentID: attachmentID,
            maxBytes: maxPDFBytes
        )
        guard pdf.report.status == .extracted, let markdown = pdf.extractedMarkdown else { return nil }
        let body = markdown.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        let rewritten = "# Extracted attachment: \(title)\n\n\(body)"
        return AttachmentExtractionResult(
            report: AgentAttachmentExtractionReport(
                attachmentID: attachmentID,
                engine: .builtinIWorkText,
                status: .extracted,
                capabilitiesUsed: [capability, "pdf-selectable-text"],
                startedAt: startedAt,
                completedAt: Date()
            ),
            extractedMarkdown: rewritten,
            previewText: preview(rewritten)
        )
    }

    private static func extractedResult(
        text: String,
        title: String,
        attachmentID: String,
        capability: String,
        startedAt: Date
    ) -> AttachmentExtractionResult {
        let markdown = "# Extracted attachment: \(title)\n\n\(text)"
        return AttachmentExtractionResult(
            report: AgentAttachmentExtractionReport(
                attachmentID: attachmentID,
                engine: .builtinIWorkText,
                status: .extracted,
                capabilitiesUsed: [capability],
                startedAt: startedAt,
                completedAt: Date()
            ),
            extractedMarkdown: markdown,
            previewText: preview(markdown)
        )
    }

    private static func result(
        attachmentID: String,
        status: AgentAttachmentExtractionStatus,
        startedAt: Date,
        warnings: [String]
    ) -> AttachmentExtractionResult {
        AttachmentExtractionResult(report: AgentAttachmentExtractionReport(
            attachmentID: attachmentID,
            engine: .builtinIWorkText,
            status: status,
            warnings: warnings,
            startedAt: startedAt,
            completedAt: Date()
        ))
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = lines.joined(separator: "\n")
        return normalized.isEmpty ? nil : normalized
    }

    private static func preview(_ text: String, max: Int = 240) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }
}

private final class LegacyIWorkXMLTextCollector: NSObject, XMLParserDelegate {
    private var fragments: [String] = []
    private var depth = 0

    var text: String { fragments.joined(separator: " ") }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard depth > 0 else { return }
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { fragments.append(value) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth = max(0, depth - 1)
    }
}
