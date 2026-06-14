import Foundation
import ConnorGraphCore

public struct AttachmentTextExtractionResult: Sendable, Equatable {
    public var status: AgentAttachmentExtractionStatus
    public var markdown: String?
    public var previewText: String?

    public init(status: AgentAttachmentExtractionStatus, markdown: String? = nil, previewText: String? = nil) {
        self.status = status
        self.markdown = markdown
        self.previewText = previewText
    }
}

public enum AttachmentTextExtraction {
    public static func extract(
        fileURL: URL,
        kind: AgentAttachmentKind,
        maxBytes: Int64 = 512_000
    ) throws -> AttachmentTextExtractionResult {
        guard supports(kind: kind) else {
            return AttachmentTextExtractionResult(status: .unsupported)
        }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= maxBytes else {
            return AttachmentTextExtractionResult(status: .skippedOversize)
        }
        let data = try Data(contentsOf: fileURL)
        let text: String?
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let utf16 = String(data: data, encoding: .utf16) {
            text = utf16
        } else {
            text = nil
        }
        guard let text else {
            return AttachmentTextExtractionResult(status: .unsupported)
        }
        let markdown = renderMarkdown(text: text, kind: kind, filename: fileURL.lastPathComponent)
        return AttachmentTextExtractionResult(
            status: .extracted,
            markdown: markdown,
            previewText: makePreview(from: text)
        )
    }

    public static func supports(kind: AgentAttachmentKind) -> Bool {
        switch kind {
        case .text, .code, .markdown, .json, .csv, .html:
            return true
        default:
            return false
        }
    }

    private static func renderMarkdown(text: String, kind: AgentAttachmentKind, filename: String) -> String {
        switch kind {
        case .markdown, .text:
            return text
        case .json:
            return """
            # Extracted attachment: \(filename)

            ```json
            \(text)
            ```
            """
        case .csv:
            return """
            # Extracted attachment: \(filename)

            ```csv
            \(text)
            ```
            """
        case .html:
            return """
            # Extracted attachment: \(filename)

            ```html
            \(text)
            ```
            """
        case .code:
            return """
            # Extracted attachment: \(filename)

            ```
            \(text)
            ```
            """
        default:
            return text
        }
    }

    private static func makePreview(from text: String, maxCharacters: Int = 240) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "…"
    }
}
