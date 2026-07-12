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
}

public actor NoteImportAttachmentImporter {
    private let store: AppSessionAttachmentStore
    private var importedBySessionAndHash: [String: AgentMessageAttachmentRef] = [:]
    public init(store: AppSessionAttachmentStore) { self.store = store }

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
        if let existing = importedBySessionAndHash[key] { return .init(attachment: attachment, messageRef: existing, reused: true) }
        let manifest = try store.importFile(at: url, sessionID: sessionID)
        importedBySessionAndHash[key] = manifest.messageRef
        return .init(attachment: attachment, messageRef: manifest.messageRef, reused: false)
    }

    public func importAttachments(_ attachments: [ImportedNoteAttachment], sessionID: String, authorizedRoot: NoteImportSourceAccessLease? = nil) throws -> [NoteImportAttachmentImportResult] {
        try attachments.map { try importAttachment($0, sessionID: sessionID, authorizedRoot: authorizedRoot) }
    }
}
