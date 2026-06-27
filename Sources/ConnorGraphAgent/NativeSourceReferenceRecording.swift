import Foundation
import ConnorGraphCore

public struct NativeSourceReference: Codable, Sendable, Equatable, Identifiable {
    public enum SourceKind: String, Codable, Sendable, Equatable, CaseIterable {
        case mail
        case calendar
        case rss
        case browserHistory = "browser_history"
    }

    public enum ReferenceStrength: String, Codable, Sendable, Equatable, CaseIterable {
        case summaryCandidate = "summary_candidate"
        case detailRead = "detail_read"
        case fullEventResult = "full_event_result"
    }

    public var id: String { deduplicationKey }
    public var sourceKind: SourceKind
    public var sourceRecordID: String
    public var title: String
    public var content: String
    public var occurredAt: Date
    public var accountID: String?
    public var sessionID: String?
    public var url: String?
    public var referenceStrength: ReferenceStrength
    public var toolName: String
    public var toolCallID: String
    public var runID: String
    public var query: String?
    public var metadata: [String: String]

    public init(
        sourceKind: SourceKind,
        sourceRecordID: String,
        title: String,
        content: String,
        occurredAt: Date,
        accountID: String? = nil,
        sessionID: String? = nil,
        url: String? = nil,
        referenceStrength: ReferenceStrength,
        toolName: String,
        toolCallID: String,
        runID: String,
        query: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sourceKind = sourceKind
        self.sourceRecordID = sourceRecordID
        self.title = title
        self.content = content
        self.occurredAt = occurredAt
        self.accountID = accountID
        self.sessionID = sessionID
        self.url = url
        self.referenceStrength = referenceStrength
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.runID = runID
        self.query = query
        self.metadata = metadata
    }

    public var deduplicationKey: String {
        [
            "native-ref",
            sourceKind.rawValue,
            sourceRecordID,
            referenceStrength.rawValue,
            stableContentFingerprint
        ].map(Self.sanitizeKeyComponent).joined(separator: ":")
    }

    public var baseMetadata: [String: String] {
        var values = metadata
        values["native_source_kind"] = sourceKind.rawValue
        values["native_source_record_id"] = sourceRecordID
        values["reference_strength"] = referenceStrength.rawValue
        values["tool_name"] = toolName
        values["tool_call_id"] = toolCallID
        values["run_id"] = runID
        values["deduplication_key"] = deduplicationKey
        if let query { values["query"] = query }
        if let url { values["url"] = url }
        return values
    }

    private var stableContentFingerprint: String {
        Self.fnv1a64Hex([
            title,
            content,
            url ?? "",
            query ?? ""
        ].joined(separator: "\n"))
    }

    private static func sanitizeKeyComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}

public protocol NativeSourceReferenceRecording: Sendable {
    func record(_ references: [NativeSourceReference]) async
}

public struct NoopNativeSourceReferenceRecorder: NativeSourceReferenceRecording {
    public init() {}
    public func record(_ references: [NativeSourceReference]) async {}
}

public extension NativeSourceReference {
    static func mailSummary(_ summary: MailMessageSummary, query: String?, toolName: String, context: AgentToolExecutionContext) -> NativeSourceReference {
        NativeSourceReference(
            sourceKind: .mail,
            sourceRecordID: summary.id.rawValue,
            title: summary.subject,
            content: mailSummaryContent(summary),
            occurredAt: summary.date,
            accountID: summary.accountID.rawValue,
            sessionID: context.sessionID,
            referenceStrength: .summaryCandidate,
            toolName: toolName,
            toolCallID: context.toolCallID,
            runID: context.runID,
            query: query,
            metadata: [
                "mail_message_id": summary.id.rawValue,
                "mailbox_id": summary.mailboxID.rawValue,
                "from": summary.from.email,
                "has_attachments": String(summary.hasAttachments)
            ]
        )
    }

    static func mailDetail(_ detail: MailMessageDetail, includeBody: Bool, toolName: String, context: AgentToolExecutionContext) -> NativeSourceReference {
        let bodyText: String
        if includeBody, let body = detail.body {
            bodyText = body.plainText?.text
                ?? body.htmlText?.text
                ?? body.redactedPreview
        } else {
            bodyText = detail.body?.redactedPreview ?? detail.summary.snippet
        }
        var metadata = mailSummaryMetadata(detail.summary)
        metadata["include_body"] = String(includeBody)
        metadata["body_hash"] = detail.body?.bodyHash ?? ""
        metadata["attachment_count"] = String(detail.attachments.count)
        return NativeSourceReference(
            sourceKind: .mail,
            sourceRecordID: detail.id.rawValue,
            title: detail.summary.subject,
            content: mailSummaryContent(detail.summary) + "\n\nBody:\n" + bodyText,
            occurredAt: detail.summary.date,
            accountID: detail.summary.accountID.rawValue,
            sessionID: context.sessionID,
            referenceStrength: .detailRead,
            toolName: toolName,
            toolCallID: context.toolCallID,
            runID: context.runID,
            metadata: metadata
        )
    }

    private static func mailSummaryContent(_ summary: MailMessageSummary) -> String {
        """
        Subject: \(summary.subject)
        From: \(summary.from.name.map { "\($0) <\(summary.from.email)>" } ?? summary.from.email)
        To: \(summary.to.map(\.email).joined(separator: ", "))
        Date: \(ISO8601DateFormatter().string(from: summary.date))
        Snippet: \(summary.snippet)
        """
    }

    private static func mailSummaryMetadata(_ summary: MailMessageSummary) -> [String: String] {
        [
            "mail_message_id": summary.id.rawValue,
            "mailbox_id": summary.mailboxID.rawValue,
            "from": summary.from.email,
            "has_attachments": String(summary.hasAttachments)
        ]
    }

    static func calendarEvent(_ event: CalendarEvent, query: String?, strength: ReferenceStrength, toolName: String, context: AgentToolExecutionContext) -> NativeSourceReference {
        NativeSourceReference(
            sourceKind: .calendar,
            sourceRecordID: event.id.rawValue,
            title: event.title,
            content: CalendarEventMemoryContentFormatter.format(event: event),
            occurredAt: event.start.date,
            sessionID: context.sessionID,
            referenceStrength: strength,
            toolName: toolName,
            toolCallID: context.toolCallID,
            runID: context.runID,
            query: query,
            metadata: [
                "calendar_event_id": event.id.rawValue,
                "calendar_id": event.calendarID.rawValue,
                "event_start": ISO8601DateFormatter().string(from: event.start.date),
                "event_end": ISO8601DateFormatter().string(from: event.end.date),
                "is_all_day": String(event.isAllDay)
            ]
        )
    }

    static func rssSummary(_ summary: RSSItemSummary, query: String?, toolName: String, context: AgentToolExecutionContext) -> NativeSourceReference {
        NativeSourceReference(
            sourceKind: .rss,
            sourceRecordID: summary.id.rawValue,
            title: summary.title,
            content: rssSummaryContent(summary),
            occurredAt: summary.publishedAt,
            accountID: summary.sourceID.rawValue,
            sessionID: context.sessionID,
            url: summary.link?.absoluteString,
            referenceStrength: .summaryCandidate,
            toolName: toolName,
            toolCallID: context.toolCallID,
            runID: context.runID,
            query: query,
            metadata: rssSummaryMetadata(summary)
        )
    }

    static func rssDetail(_ detail: RSSItemDetail, includeContent: Bool, toolName: String, context: AgentToolExecutionContext) -> NativeSourceReference {
        let contentText: String
        if includeContent, let content = detail.content {
            contentText = content.safeMarkdown.isEmpty ? content.plainText : content.safeMarkdown
        } else {
            contentText = detail.summary.snippet
        }
        var metadata = rssSummaryMetadata(detail.summary)
        metadata["include_content"] = String(includeContent)
        metadata["content_byte_count"] = String(detail.content?.byteCount ?? 0)
        metadata["content_was_truncated"] = String(detail.content?.wasTruncated ?? false)
        return NativeSourceReference(
            sourceKind: .rss,
            sourceRecordID: detail.id.rawValue,
            title: detail.summary.title,
            content: rssSummaryContent(detail.summary) + "\n\nContent:\n" + contentText,
            occurredAt: detail.summary.publishedAt,
            accountID: detail.summary.sourceID.rawValue,
            sessionID: context.sessionID,
            url: detail.summary.link?.absoluteString,
            referenceStrength: .detailRead,
            toolName: toolName,
            toolCallID: context.toolCallID,
            runID: context.runID,
            metadata: metadata
        )
    }

    private static func rssSummaryContent(_ summary: RSSItemSummary) -> String {
        """
        Title: \(summary.title)
        Author: \(summary.author ?? "")
        Published: \(ISO8601DateFormatter().string(from: summary.publishedAt))
        Link: \(summary.link?.absoluteString ?? "")
        Snippet: \(summary.snippet)
        """
    }

    private static func rssSummaryMetadata(_ summary: RSSItemSummary) -> [String: String] {
        [
            "rss_item_id": summary.id.rawValue,
            "rss_source_id": summary.sourceID.rawValue,
            "content_hash": summary.contentHash,
            "author": summary.author ?? ""
        ]
    }
}
