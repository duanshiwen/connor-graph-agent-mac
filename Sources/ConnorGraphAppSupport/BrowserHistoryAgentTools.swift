import Foundation
import ConnorGraphAgent

public struct BrowserHistorySearchResult: Codable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var title: String
    public var sessionID: String
    public var sessionTitle: String
    public var visitedAt: Date
    public var contentFetchStatus: BrowserHistoryContentFetchStatus?
    public var contentFetchedAt: Date?
    public var contentFetchError: String?
    public var hasContentMarkdown: Bool
    public var contentPreview: String?

    public init(record: BrowserHistoryRecord, previewCharacterLimit: Int = 500) {
        self.id = record.id.uuidString
        self.url = record.url
        self.title = record.title
        self.sessionID = record.sessionID
        self.sessionTitle = record.sessionTitle
        self.visitedAt = record.visitedAt
        self.contentFetchStatus = record.contentFetchStatus
        self.contentFetchedAt = record.contentFetchedAt
        self.contentFetchError = record.contentFetchError
        self.hasContentMarkdown = !(record.contentMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if let markdown = record.contentMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), !markdown.isEmpty {
            self.contentPreview = String(markdown.prefix(max(0, previewCharacterLimit)))
        } else {
            self.contentPreview = nil
        }
    }
}

public struct BrowserHistoryDetailResult: Codable, Equatable, Sendable {
    public var id: String
    public var url: String
    public var title: String
    public var sessionID: String
    public var sessionTitle: String
    public var visitedAt: Date
    public var contentMarkdown: String?
    public var contentFetchedAt: Date?
    public var contentFetchStatus: BrowserHistoryContentFetchStatus?
    public var contentFetchError: String?

    public init(record: BrowserHistoryRecord) {
        self.id = record.id.uuidString
        self.url = record.url
        self.title = record.title
        self.sessionID = record.sessionID
        self.sessionTitle = record.sessionTitle
        self.visitedAt = record.visitedAt
        self.contentMarkdown = record.contentMarkdown
        self.contentFetchedAt = record.contentFetchedAt
        self.contentFetchStatus = record.contentFetchStatus
        self.contentFetchError = record.contentFetchError
    }
}

private enum BrowserHistoryToolJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

public struct BrowserHistorySearchTool: AgentTool {
    public let store: BrowserHistoryStore
    public var name: String { "browser_history_search" }
    public var description: String { "Search saved browser history records by URL, title, session title, or saved page markdown. Returns summaries/previews so the model can choose which page bodies to read." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "query": .string(description: "Search query"),
            "limit": .integer(description: "Maximum history summaries to return"),
            "previewCharacters": .integer(description: "Maximum saved markdown preview characters per result")
        ], required: ["query"])
    }

    public init(store: BrowserHistoryStore) {
        self.store = store
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let query = arguments.string("query") ?? ""
        let limit = max(1, min(arguments.int("limit") ?? 20, 100))
        let previewCharacters = max(0, min(arguments.int("previewCharacters") ?? 500, 2_000))
        let records = Array(store.searchHistory(query: query).sorted { $0.visitedAt > $1.visitedAt }.prefix(limit))
        let results = records.map { BrowserHistorySearchResult(record: $0, previewCharacterLimit: previewCharacters) }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Found \(results.count) browser history summaries; call browser_history_get for selected pages to read saved page markdown",
            contentJSON: try BrowserHistoryToolJSON.encode(results)
        )
    }
}

public struct BrowserHistoryGetTool: AgentTool {
    public let store: BrowserHistoryStore
    public var name: String { "browser_history_get" }
    public var description: String { "Get a saved browser history record by ID, including saved page markdown content when available." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "recordID": .string(description: "Browser history record UUID returned by browser_history_search")
        ], required: ["recordID"])
    }

    public init(store: BrowserHistoryStore) {
        self.store = store
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawID = arguments.string("recordID"), let id = UUID(uuidString: rawID) else {
            throw AgentToolError.invalidArguments("recordID must be a valid browser history UUID")
        }
        guard let record = store.record(id: id) else {
            throw AgentToolError.invalidArguments("Browser history record not found: \(rawID)")
        }
        let detail = BrowserHistoryDetailResult(record: record)
        let hasMarkdown = !(detail.contentMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: hasMarkdown ? "Loaded browser history record with saved page markdown" : "Loaded browser history record; saved page markdown is unavailable or empty",
            contentJSON: try BrowserHistoryToolJSON.encode(detail)
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerBrowserHistoryTools(store: BrowserHistoryStore) {
        register(BrowserHistorySearchTool(store: store))
        register(BrowserHistoryGetTool(store: store))
    }
}
