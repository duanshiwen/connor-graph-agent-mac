import Foundation
import ConnorGraphCore

public enum AttachmentPreviewBodyMode: String, Sendable, Codable, Equatable {
    case markdown
    case monospaced
    case plain
    case image
}

public struct AttachmentPreviewModel: Sendable, Equatable, Identifiable {
    public var id: String { attachment.id }
    public var attachment: AgentMessageAttachmentRef
    public var manifest: AgentAttachmentManifest?
    public var title: String
    public var subtitle: String
    public var body: String
    public var bodyMode: AttachmentPreviewBodyMode
    public var sourceRelativePath: String?
    public var sourceFileURL: URL?
    public var errorMessage: String?

    public init(
        attachment: AgentMessageAttachmentRef,
        manifest: AgentAttachmentManifest? = nil,
        title: String,
        subtitle: String,
        body: String,
        bodyMode: AttachmentPreviewBodyMode,
        sourceRelativePath: String? = nil,
        sourceFileURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.attachment = attachment
        self.manifest = manifest
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.bodyMode = bodyMode
        self.sourceRelativePath = sourceRelativePath
        self.sourceFileURL = sourceFileURL
        self.errorMessage = errorMessage
    }
}

public struct AttachmentPreviewLoader: Sendable {
    public var store: AppSessionAttachmentStore

    public init(store: AppSessionAttachmentStore) {
        self.store = store
    }

    public func load(
        sessionID: String,
        attachment: AgentMessageAttachmentRef
    ) -> AttachmentPreviewModel {
        do {
            let manifest = try store.loadManifest(sessionID: sessionID, attachmentID: attachment.id)
            let subtitle = Self.subtitle(for: manifest)
            let originalFileURL = store.paths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(manifest.storedRelativePath)
            if manifest.kind == .image {
                return AttachmentPreviewModel(
                    attachment: attachment,
                    manifest: manifest,
                    title: attachment.displayName,
                    subtitle: subtitle,
                    body: "",
                    bodyMode: .image,
                    sourceRelativePath: manifest.storedRelativePath,
                    sourceFileURL: originalFileURL,
                    errorMessage: nil
                )
            }
            guard let relativePath = manifest.extractedTextRelativePath, !relativePath.isEmpty else {
                let statusMessage = Self.statusMessage(for: manifest)
                let fallback = attachment.previewText ?? manifest.previewText ?? statusMessage
                return AttachmentPreviewModel(
                    attachment: attachment,
                    manifest: manifest,
                    title: attachment.displayName,
                    subtitle: subtitle,
                    body: fallback,
                    bodyMode: Self.bodyMode(for: manifest),
                    sourceRelativePath: manifest.storedRelativePath,
                    sourceFileURL: originalFileURL,
                    errorMessage: statusMessage
                )
            }
            let url = store.paths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(relativePath)
            let body = try String(contentsOf: url, encoding: .utf8)
            return AttachmentPreviewModel(
                attachment: attachment,
                manifest: manifest,
                title: manifest.displayName,
                subtitle: subtitle,
                body: body.isEmpty ? "当前附件预览为空。" : body,
                bodyMode: Self.bodyMode(for: manifest),
                sourceRelativePath: relativePath,
                sourceFileURL: originalFileURL,
                errorMessage: nil
            )
        } catch {
            let fallback = attachment.previewText ?? "无法读取附件预览：\(error)"
            return AttachmentPreviewModel(
                attachment: attachment,
                manifest: nil,
                title: attachment.displayName,
                subtitle: Self.subtitle(for: attachment),
                body: fallback,
                bodyMode: Self.bodyMode(for: attachment.kind),
                sourceRelativePath: nil,
                errorMessage: "无法读取附件预览：\(error)"
            )
        }
    }

    private static func subtitle(for manifest: AgentAttachmentManifest) -> String {
        let size = ByteCountFormatter.string(fromByteCount: manifest.byteCount, countStyle: .file)
        return "\(manifest.kind.rawValue) · \(size) · \(manifest.extractionStatus.rawValue)"
    }

    private static func subtitle(for attachment: AgentMessageAttachmentRef) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)
        return "\(attachment.kind.rawValue) · \(size) · \(attachment.extractionStatus.rawValue)"
    }

    private static func statusMessage(for manifest: AgentAttachmentManifest) -> String {
        switch manifest.extractionStatus {
        case .pending:
            return "附件已保存，正在等待文字解析；解析完成前不会进入 prompt。"
        case .unsupported:
            let warning = manifest.extractionReports.last?.warnings.first
            return warning.map { "附件已保存，但当前无法转换为文字：\($0)" } ?? "附件已保存，但当前无法转换为文字。"
        case .failed:
            let error = manifest.extractionReports.last?.errors.first
            return error.map { "附件已保存，但文字解析失败：\($0)" } ?? "附件已保存，但文字解析失败。"
        case .skippedOversize:
            return "附件已保存，但因超过解析大小限制，未转换为文字。"
        case .extracted:
            return "当前附件没有可预览文本。"
        }
    }

    private static func bodyMode(for manifest: AgentAttachmentManifest) -> AttachmentPreviewBodyMode {
        bodyMode(for: manifest.kind)
    }

    private static func bodyMode(for kind: AgentAttachmentKind) -> AttachmentPreviewBodyMode {
        switch kind {
        case .markdown:
            return .markdown
        case .code, .json, .csv:
            return .monospaced
        case .text:
            return .plain
        case .image:
            return .image
        case .pdf, .document, .spreadsheet, .presentation:
            return .markdown
        default:
            return .plain
        }
    }
}
