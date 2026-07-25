import CryptoKit
import Foundation
import ConnorGraphCore

public protocol NoteProjectionSynchronizing: Sendable {
    func synchronize(session: AgentSession, origin: NoteOriginKind) throws
    func remove(sessionID: String, deletedAt: Date) throws
}

public struct AppNoteProjectionService: NoteProjectionSynchronizing, Sendable {
    public let repository: AppNoteRepository

    public init(repository: AppNoteRepository) { self.repository = repository }

    public func synchronize(session: AgentSession, origin: NoteOriginKind = .native) throws {
        guard session.governance.kind == .note, !session.governance.isDeleted,
              let sourceMessage = session.messages.first else {
            if session.governance.isDeleted || session.governance.kind != .note {
                try repository.delete(sessionID: session.id, deletedAt: session.governance.deletedAt ?? Date())
            }
            return
        }
        let hash = Self.contentHash(sourceMessage.content)
        let existing = try repository.note(sessionID: session.id)
        if existing?.sourceMessageID == sourceMessage.id,
           existing?.contentHash == hash,
           existing?.title == session.title,
           existing?.sourceUpdatedAt == session.updatedAt { return }
        try repository.upsert(NoteRecord(
            id: existing?.id ?? Self.noteID(sessionID: session.id), sessionID: session.id,
            sourceMessageID: sourceMessage.id, title: session.title, body: sourceMessage.content,
            contentHash: hash, sourceUpdatedAt: session.updatedAt,
            createdAt: existing?.createdAt ?? session.createdAt, updatedAt: Date(),
            indexVersion: existing?.indexVersion ?? 0, projectionStatus: .projected,
            indexedAt: existing?.indexedAt, failureCount: 0,
            originKind: existing?.originKind == .imported ? .imported : origin,
            importItemID: existing?.importItemID, importSourceID: existing?.importSourceID,
            sourceKind: existing?.sourceKind, sourceIdentity: existing?.sourceIdentity,
            externalID: existing?.externalID, relativePath: existing?.relativePath,
            sourceCreatedAt: existing?.sourceCreatedAt
        ))
    }

    public func remove(sessionID: String, deletedAt: Date = Date()) throws {
        try repository.delete(sessionID: sessionID, deletedAt: deletedAt)
    }

    public static func noteID(sessionID: String) -> String { "note:\(sessionID)" }

    public static func contentHash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
