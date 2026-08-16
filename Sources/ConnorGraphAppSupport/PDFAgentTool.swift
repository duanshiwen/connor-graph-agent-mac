import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum GeneratePDFAgentToolError: Error, Sendable, Equatable, LocalizedError {
    case emptyContent
    case renderFailed(String)
    case unexpectedKind

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "PDF 内容不能为空。"
        case .renderFailed(let detail):
            return "PDF 生成失败：\(detail)"
        case .unexpectedKind:
            return "生成的附件不是 PDF。"
        }
    }
}

public struct PDFAgentToolResultPayload: Codable, Sendable, Equatable {
    public var attachment: AgentMessageAttachmentRef
    public var markdown: String
    public var localFileURL: URL
    public var fileName: String
    public var byteCount: Int64
    public var pageCount: Int

    public init(attachment: AgentMessageAttachmentRef, markdown: String, localFileURL: URL, fileName: String, byteCount: Int64, pageCount: Int) {
        self.attachment = attachment
        self.markdown = markdown
        self.localFileURL = localFileURL
        self.fileName = fileName
        self.byteCount = byteCount
        self.pageCount = pageCount
    }
}

/// 生成 PDF 文档：把标题 + Markdown 风格正文渲染为 A4 分页 PDF，并作为
/// 当前会话的附件持久化。适合「把内容做成 PDF 文档/报告」的明确请求；
/// 不要在用户只是要普通对话回复时调用。
public struct GeneratePDFAgentTool: AgentTool {
    public let name = "generate_pdf"
    public let description = "Generate a polished A4 PDF document from the given content and attach it to the current Connor session. Use only when the user explicitly asks to create a PDF / document / report / 生成PDF / 导出为PDF. The content supports # / ## / ### headings, - bullets, numbered lists and plain paragraphs; Chinese is fully supported."
    public let permission: AgentPermissionCapability = .mutateSessionStatus
    public let inputSchema = AgentToolInputSchema.closedObject(
        properties: [
            "title": .string(description: "Optional document title shown at the top of the first page. Defaults to the file name."),
            "content": .string(description: "Document body in Markdown style: # / ## / ### headings, - bullets, numbered lists, blank-line separated paragraphs. Required."),
            "fileName": .string(description: "Optional PDF file name without extension. Defaults to the title or 'document'.")
        ],
        required: ["content"]
    )
    public let inputExamples: [[String: SendableJSONValue]] = [
        [
            "title": .string("季度总结"),
            "content": .string("# 季度总结\n\n## 进展\n\n- 完成了导入\n- 修复了崩溃"),
            "fileName": .string("季度总结")
        ]
    ]

    private let store: AppSessionAttachmentStore

    public init(store: AppSessionAttachmentStore) {
        self.store = store
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "title": ["标题", "name"],
            "content": ["body", "text", "markdown", "正文"],
            "fileName": ["filename", "file_name", "文件名"]
        ])
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let content = arguments.string("content")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = arguments.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fileName = arguments.string("fileName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw GeneratePDFAgentToolError.emptyContent }

        let data: Data
        do {
            data = try PDFDocumentGenerator.render(title: title.nilIfEmpty, content: content)
        } catch let error as PDFDocumentGeneratorError {
            throw GeneratePDFAgentToolError.renderFailed(error.errorDescription ?? "未知错误")
        }
        let pageCount = PDFDocumentGenerator.pageCount(of: data)

        let baseName = fileName.isEmpty ? (title.isEmpty ? "document" : title) : fileName
        let safeBase = baseName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let displayName = (safeBase.isEmpty ? "document" : safeBase) + ".pdf"

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-pdf-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        let manifest = try store.importFile(at: temporaryURL, sessionID: context.sessionID, origin: .toolGenerated)
        guard manifest.kind == .pdf else { throw GeneratePDFAgentToolError.unexpectedKind }

        let localFileURL = store.paths.sessionArtifactDirectories(sessionID: context.sessionID).root
            .appendingPathComponent(manifest.storedRelativePath)
        let markdown = "[\(displayName)](\(localFileURL.absoluteString))"
        let payload = PDFAgentToolResultPayload(
            attachment: manifest.messageRef,
            markdown: markdown,
            localFileURL: localFileURL,
            fileName: displayName,
            byteCount: manifest.byteCount,
            pageCount: pageCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "PDF 已生成（\(pageCount) 页）：\(displayName)\n\(markdown)",
            contentJSON: String(decoding: try encoder.encode(payload), as: UTF8.self)
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerPDFGenerationTool(store: AppSessionAttachmentStore) {
        register(GeneratePDFAgentTool(store: store))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
