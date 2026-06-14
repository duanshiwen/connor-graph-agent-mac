import Foundation
import ConnorGraphCore

public enum AttachmentPreviewBodyMode: String, Sendable, Codable, Equatable {
    case markdown
    case monospaced
    case plain
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
    public var errorMessage: String?

    public init(
        attachment: AgentMessageAttachmentRef,
        manifest: AgentAttachmentManifest? = nil,
        title: String,
        subtitle: String,
        body: String,
        bodyMode: AttachmentPreviewBodyMode,
        sourceRelativePath: String? = nil,
        errorMessage: String? = nil
    ) {
        self.attachment = attachment
        self.manifest = manifest
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.bodyMode = bodyMode
        self.sourceRelativePath = sourceRelativePath
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
            guard let relativePath = manifest.extractedTextRelativePath, !relativePath.isEmpty else {
                let fallback = attachment.previewText ?? manifest.previewText ?? "当前附件没有可预览文本。"
                return AttachmentPreviewModel(
                    attachment: attachment,
                    manifest: manifest,
                    title: attachment.displayName,
                    subtitle: subtitle,
                    body: fallback,
                    bodyMode: Self.bodyMode(for: manifest),
                    sourceRelativePath: nil,
                    errorMessage: "当前附件没有可预览文本。"
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
        default:
            return .plain
        }
    }
}
