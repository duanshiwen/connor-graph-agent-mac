import Foundation
import ConnorGraphCore

public enum NoteImportAttachmentImporterError: Error, Sendable, Equatable {
    case missingSourcePath(String)
    case missingSourceFile(String)
    case hashMismatch(expected: String, actual: String)
    case byteCountMismatch(expected: Int64, actual: Int64)
}

public struct NoteImportAttachmentImportResult: Sendable, Equatable {
    public var attachment: ImportedNoteAttachment
    public var messageRef: AgentMessageAttachmentRef
    public var reused: Bool
    /// 附件在会话附件存储中的实际文件 URL（供笔记 Markdown 图片引用改写）。
    public var storedFileURL: URL
}

public actor NoteImportAttachmentImporter {
    private let store: AppSessionAttachmentStore
    private let policy: AttachmentImportPolicy
    private var importedBySessionAndHash: [String: AgentAttachmentManifest] = [:]

    /// 笔记导入与日常聊天共用同一附件策略：
    /// 单文件上限 512MB（图片 5MB），内容总量按 token 上限校验，超限拒绝而非截断。
    public init(
        store: AppSessionAttachmentStore,
        policy: AttachmentImportPolicy = AttachmentImportPolicy()
    ) {
        self.store = store
        self.policy = policy
    }

    public func importAttachment(_ attachment: ImportedNoteAttachment, sessionID: String, authorizedRoot: NoteImportSourceAccessLease? = nil) throws -> NoteImportAttachmentImportResult {
        guard let path = attachment.sourcePath else { throw NoteImportAttachmentImporterError.missingSourcePath(attachment.displayName) }
        var url = URL(fileURLWithPath: path)
        if let authorizedRoot { url = try authorizedRoot.validate(url) }
        guard FileManager.default.fileExists(atPath: url.path) else { throw NoteImportAttachmentImporterError.missingSourceFile(path) }
        let bytes = try AppSessionAttachmentStore.byteCount(forItemAt: url)
        if let expected = attachment.byteCount, expected != bytes { throw NoteImportAttachmentImporterError.byteCountMismatch(expected: expected, actual: bytes) }
        let hash = try AppSessionAttachmentStore.sha256Hex(forItemAt: url)
        if let expected = attachment.contentHash, expected.lowercased() != hash.lowercased() { throw NoteImportAttachmentImporterError.hashMismatch(expected: expected, actual: hash) }
        let key = sessionID + ":" + hash
        let directories = try store.paths.ensureSessionArtifactDirectories(sessionID: sessionID)
        if let existing = importedBySessionAndHash[key] {
            return .init(
                attachment: attachment,
                messageRef: existing.messageRef,
                reused: true,
                storedFileURL: directories.root.appendingPathComponent(existing.storedRelativePath)
            )
        }
        let manifest = try store.importFile(at: url, sessionID: sessionID, policy: policy)
        importedBySessionAndHash[key] = manifest
        return .init(
            attachment: attachment,
            messageRef: manifest.messageRef,
            reused: false,
            storedFileURL: directories.root.appendingPathComponent(manifest.storedRelativePath)
        )
    }

    public func importAttachments(_ attachments: [ImportedNoteAttachment], sessionID: String, authorizedRoot: NoteImportSourceAccessLease? = nil) throws -> [NoteImportAttachmentImportResult] {
        try attachments.map { try importAttachment($0, sessionID: sessionID, authorizedRoot: authorizedRoot) }
    }
}
