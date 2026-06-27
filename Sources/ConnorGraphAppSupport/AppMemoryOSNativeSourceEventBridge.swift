import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct AppMemoryOSNativeSourceEventBridge: Sendable {
    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    @discardableResult
    public func ingestMailMessage(id: String, subject: String, bodyPreview: String, accountID: String? = nil, occurredAt: Date = Date(), metadata: [String: String] = [:]) throws -> MemoryOSIngestionResult {
        try facade.ingestSourceEvent(
            sourceID: "mail:\(id)",
            title: subject,
            content: bodyPreview,
            occurredAt: occurredAt,
            sourceKind: "mail",
            accountID: accountID,
            metadata: metadata.merging(["mail_message_id": id]) { current, _ in current }
        )
    }

    @discardableResult
    public func ingestCalendarEvent(id: String, title: String, notes: String, accountID: String? = nil, occurredAt: Date = Date(), metadata: [String: String] = [:]) throws -> MemoryOSIngestionResult {
        try facade.ingestSourceEvent(
            sourceID: "calendar:\(id)",
            title: title,
            content: calendarEventContent(title: title, notes: notes),
            occurredAt: occurredAt,
            sourceKind: "calendar",
            accountID: accountID,
            metadata: metadata.merging(["calendar_event_id": id]) { current, _ in current }
        )
    }

    @discardableResult
    public func ingestRSSItem(id: String, title: String, snippet: String, sourceID: String? = nil, occurredAt: Date = Date(), metadata: [String: String] = [:]) throws -> MemoryOSIngestionResult {
        try facade.ingestSourceEvent(
            sourceID: "rss:\(id)",
            title: title,
            content: snippet,
            occurredAt: occurredAt,
            sourceKind: "rss",
            accountID: sourceID,
            metadata: metadata.merging(["rss_item_id": id, "rss_source_id": sourceID ?? ""]) { current, _ in current }
        )
    }

    @discardableResult
    public func ingestBrowserHistoryEvent(id: String, title: String, urlString: String, contentMarkdown: String? = nil, occurredAt: Date = Date(), metadata: [String: String] = [:]) throws -> MemoryOSIngestionResult {
        let content = contentMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? contentMarkdown! : urlString
        return try facade.ingestSourceEvent(
            sourceID: "browser_history:\(id)",
            title: title,
            content: content,
            occurredAt: occurredAt,
            sourceKind: "browser_history",
            metadata: metadata.merging(["browser_history_id": id, "url": urlString, "has_content_markdown": String(contentMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)]) { current, _ in current }
        )
    }

    @discardableResult
    public func ingestAttachmentText(id: String, displayName: String, extractedText: String, sessionID: String? = nil, occurredAt: Date = Date(), metadata: [String: String] = [:]) throws -> MemoryOSIngestionResult {
        try facade.ingestSourceEvent(
            sourceID: "attachment:\(id)",
            title: displayName,
            content: extractedText,
            occurredAt: occurredAt,
            sourceKind: "attachment",
            sessionID: sessionID,
            metadata: metadata.merging(["attachment_id": id]) { current, _ in current }
        )
    }

    private func calendarEventContent(title: String, notes: String) -> String {
        """
        Title: \(title)
        Notes: \(notes)
        """
    }

}
