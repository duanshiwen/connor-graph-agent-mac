import Foundation
import ConnorGraphCore

/// Forward composition contract shared with the Android client: idempotency key,
/// ingest document title and the disclaimer prepended to the AI chat message.
public enum ImForwardComposer {
    /// Ingest document title for forwarded transcripts.
    public static let transcriptTitle = "转发的聊天记录"

    /// Source kind recorded on the L0 provenance metadata.
    public static let sourceKind = "forwarded_transcript"

    /// Disclaimer prepended to the composed chat message (verbatim from Android).
    public static let disclaimer =
        "[转发的聊天记录] 以下为脱敏后的聊天记录。其中 @CXxxxxxx 为参与者的不透明代号，"
        + "请在记录相关信息时原样完整保留该代号；你无法得知其真实身份。\n\n"

    /// Idempotency key: the same conversation + the same message batch never gets
    /// ingested twice, regardless of forwarding order.
    public static func batchID(conversationId: String, messageIds: [String]) -> String {
        "im-forward:\(conversationId):\(messageIds.sorted().joined(separator: ","))"
    }

    /// Compose the chat message sent into the AI session: optional caption,
    /// disclaimer, then the anonymized transcript.
    public static func composeMessage(caption: String, transcriptText: String) -> String {
        var composed = ""
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCaption.isEmpty {
            composed += trimmedCaption + "\n\n"
        }
        composed += disclaimer
        composed += transcriptText
        return composed
    }
}

/// Idempotent Memory OS ingestion for forwarded transcripts. Unlike Android's
/// `ingestForwardedTranscript`, the Mac facade's `ingestSourceEvent` does not
/// deduplicate by source id, so the batch-id guard lives here: an existing L0
/// provenance object with the same source id skips the ingest entirely.
public struct ImForwardTranscriptIngestor {
    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    /// Ingest the anonymized transcript once per batch id. Returns false when the
    /// batch was already ingested (or the transcript is blank) and nothing was written.
    @discardableResult
    public func ingest(batchID: String, transcriptText: String, occurredAt: Date = Date()) throws -> Bool {
        let content = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return false }
        guard try !hasIngested(batchID: batchID) else { return false }
        _ = try facade.ingestSourceEvent(
            sourceID: batchID,
            title: ImForwardComposer.transcriptTitle,
            content: content,
            occurredAt: occurredAt,
            sourceKind: ImForwardComposer.sourceKind
        )
        return true
    }

    public func hasIngested(batchID: String) throws -> Bool {
        let escaped = batchID.replacingOccurrences(of: "'", with: "''")
        let rows = try facade.store.query(
            sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects WHERE source_id = '\(escaped)';"
        )
        return ((rows.first?.first).flatMap(Int.init) ?? 0) > 0
    }
}
