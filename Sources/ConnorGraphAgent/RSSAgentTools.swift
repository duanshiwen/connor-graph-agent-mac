import Foundation
import ConnorGraphCore

public protocol AgentRSSRuntime: Sendable {
    func listSources(runID: String?, sessionID: String?) async throws -> [RSSSource]
    func addSource(feedURL: URL, displayName: String?, runID: String?, sessionID: String?) async throws -> RSSSource
    func syncSource(sourceID: RSSSourceID, runID: String?, sessionID: String?) async throws -> RSSFetchResult
    func listItems(sourceID: RSSSourceID?, includeHidden: Bool, limit: Int, runID: String?, sessionID: String?) async throws -> [RSSItemSummary]
    func searchItems(_ request: RSSRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [RSSItemSummary]
    func getItem(id: RSSItemID, includeContent: Bool, runID: String?, sessionID: String?) async throws -> RSSItemDetail
    func setReadState(itemIDs: [RSSItemID], isRead: Bool, runID: String?, sessionID: String?) async throws
    func setStarState(itemIDs: [RSSItemID], isStarred: Bool, runID: String?, sessionID: String?) async throws
    func setHiddenState(itemIDs: [RSSItemID], isHidden: Bool, runID: String?, sessionID: String?) async throws
    func importOPML(_ xml: String, runID: String?, sessionID: String?) async throws -> OPMLDocument
    func exportOPML(runID: String?, sessionID: String?) async throws -> String
    func evidenceCandidate(for itemID: RSSItemID) async throws -> RSSEvidenceCandidate
}

public struct RSSRuntimeSearchRequestBridge: Sendable, Equatable {
    public var query: String
    public var sourceID: RSSSourceID?
    public var includeHidden: Bool
    public var limit: Int
    public var startDate: Date?
    public var endDate: Date?
    public var timePreset: String?
    public var timeSort: String?

    public init(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false, limit: Int = 50, startDate: Date? = nil, endDate: Date? = nil, timePreset: String? = nil, timeSort: String? = nil) {
        self.query = query
        self.sourceID = sourceID
        self.includeHidden = includeHidden
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        self.startDate = startDate
        self.endDate = endDate
        self.timePreset = timePreset
        self.timeSort = timeSort
    }
}

enum RSSJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

public struct RSSListSourcesTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_list_sources" }
    public var description: String { "List Connor-owned RSS sources. Reads are allowed and audited." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .object(properties: [:], required: []) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sources = try await runtime.listSources(runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(sources.count) RSS sources", contentJSON: try RSSJSON.encode(sources))
    }
}

public struct RSSAddSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_add_source" }
    public var description: String { "Add a governed RSS/Atom/JSON Feed source to Connor source registry." }
    public var permission: AgentPermissionCapability { .manageRSSSources }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["feedURL": .string(description: "Feed URL"), "displayName": .string(description: "Optional display name")], required: ["feedURL"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let urlString = arguments.string("feedURL"), let url = URL(string: urlString) else { throw AgentToolError.invalidArguments("feedURL is required") }
        let source = try await runtime.addSource(feedURL: url, displayName: arguments.string("displayName"), runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Added RSS source \(source.displayName)", contentJSON: try RSSJSON.encode(source))
    }
}

public struct RSSSyncSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_sync_source" }
    public var description: String { "Synchronize an existing RSS source through Connor runtime." }
    public var permission: AgentPermissionCapability { .syncRSSSources }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["sourceID": .string(description: "RSS source ID")], required: ["sourceID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let sourceID = arguments.string("sourceID") else { throw AgentToolError.invalidArguments("sourceID is required") }
        let result = try await runtime.syncSource(sourceID: RSSSourceID(rawValue: sourceID), runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Synced RSS source; inserted \(result.insertedCount), duplicates \(result.duplicateCount)", contentJSON: try RSSJSON.encode(result))
    }
}

public struct RSSListItemsTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_list_items" }
    public var description: String { "List RSS item summaries without reading full content." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["sourceID": .string(description: "Optional RSS source ID"), "includeHidden": .boolean(description: "Include hidden items"), "limit": .integer(description: "Maximum items")], required: []) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let items = try await runtime.listItems(sourceID: arguments.string("sourceID").map(RSSSourceID.init(rawValue:)), includeHidden: arguments.bool("includeHidden") ?? false, limit: NativeSearchLimitPolicy.clampListLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultListLimit), runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(items.count) RSS item summaries", contentJSON: try RSSJSON.encode(items))
    }
}

public struct RSSSearchItemsTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_search_items" }
    public var description: String { "Search Connor-owned RSS item summaries using indexed, time-aware retrieval by title, snippet, author, content, or source. Supports optional ISO-8601 startDate/endDate or timePreset; results include published/fetched time." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["query": .string(description: "Search query"), "sourceID": .string(description: "Optional RSS source ID"), "includeHidden": .boolean(description: "Include hidden"), "limit": .integer(description: "Maximum summaries"), "startDate": .string(description: "Optional ISO-8601 inclusive start timestamp for published/fetched time filtering"), "endDate": .string(description: "Optional ISO-8601 exclusive end timestamp for published/fetched time filtering"), "timePreset": .string(description: "Optional time preset such as today, last7Days, last30Days, thisWeek, lastMonth"), "timeSort": .string(description: "Optional sort: relevanceThenTimeDesc, relevanceThenTimeAsc, timeDescThenRelevance, timeAscThenRelevance")], required: ["query"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let formatter = ISO8601DateFormatter()
        let request = RSSRuntimeSearchRequestBridge(
            query: arguments.string("query") ?? "",
            sourceID: arguments.string("sourceID").map(RSSSourceID.init(rawValue:)),
            includeHidden: arguments.bool("includeHidden") ?? false,
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultListLimit),
            startDate: arguments.string("startDate").flatMap { formatter.date(from: $0) },
            endDate: arguments.string("endDate").flatMap { formatter.date(from: $0) },
            timePreset: arguments.string("timePreset"),
            timeSort: arguments.string("timeSort")
        )
        let items = try await runtime.searchItems(request, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(items.count) RSS item summaries", contentJSON: try RSSJSON.encode(items))
    }
}

public struct RSSGetItemTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_get_item" }
    public var description: String { "Get RSS item detail; content is optional and audited separately." }
    public var permission: AgentPermissionCapability { .readRSSContent }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["itemID": .string(description: "RSS item ID"), "includeContent": .boolean(description: "Include full safe content")], required: ["itemID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let itemID = arguments.string("itemID") else { throw AgentToolError.invalidArguments("itemID is required") }
        let includeContent = arguments.bool("includeContent") ?? false
        let item = try await runtime.getItem(id: RSSItemID(rawValue: itemID), includeContent: includeContent, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: includeContent ? "Read RSS item content" : "Read RSS item without content", contentJSON: try RSSJSON.encode(item))
    }
}

public struct RSSSetReadStateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_set_read_state" }
    public var description: String { "Explicitly mutate RSS read/unread state." }
    public var permission: AgentPermissionCapability { .mutateRSSState }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["itemIDs": .array(items: .string(description: "RSS item ID"), description: "Item IDs"), "isRead": .boolean(description: "Desired read state")], required: ["itemIDs", "isRead"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let ids = (arguments.array("itemIDs") ?? []).compactMap(\.stringValue).map(RSSItemID.init(rawValue:))
        try await runtime.setReadState(itemIDs: ids, isRead: arguments.bool("isRead") ?? false, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Updated read state for \(ids.count) RSS items")
    }
}

public struct RSSSetStarStateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_set_star_state" }
    public var description: String { "Explicitly mutate RSS star state." }
    public var permission: AgentPermissionCapability { .mutateRSSState }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["itemIDs": .array(items: .string(description: "RSS item ID"), description: "Item IDs"), "isStarred": .boolean(description: "Desired star state")], required: ["itemIDs", "isStarred"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let ids = (arguments.array("itemIDs") ?? []).compactMap(\.stringValue).map(RSSItemID.init(rawValue:))
        try await runtime.setStarState(itemIDs: ids, isStarred: arguments.bool("isStarred") ?? false, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Updated star state for \(ids.count) RSS items")
    }
}

public struct RSSSetHiddenStateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_set_hidden_state" }
    public var description: String { "Explicitly mutate RSS hidden state." }
    public var permission: AgentPermissionCapability { .mutateRSSState }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["itemIDs": .array(items: .string(description: "RSS item ID"), description: "Item IDs"), "isHidden": .boolean(description: "Desired hidden state")], required: ["itemIDs", "isHidden"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let ids = (arguments.array("itemIDs") ?? []).compactMap(\.stringValue).map(RSSItemID.init(rawValue:))
        try await runtime.setHiddenState(itemIDs: ids, isHidden: arguments.bool("isHidden") ?? false, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Updated hidden state for \(ids.count) RSS items")
    }
}

public struct RSSImportOPMLTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_import_opml" }
    public var description: String { "Import OPML subscriptions into Connor RSS source registry." }
    public var permission: AgentPermissionCapability { .importRSSOPML }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["opmlXML": .string(description: "OPML XML content")], required: ["opmlXML"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let document = try await runtime.importOPML(arguments.string("opmlXML") ?? "", runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Imported \(document.outlines.count) RSS subscriptions", contentJSON: try RSSJSON.encode(document))
    }
}

public struct RSSExportOPMLTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_export_opml" }
    public var description: String { "Export Connor RSS subscriptions as OPML text." }
    public var permission: AgentPermissionCapability { .exportRSSOPML }
    public var inputSchema: AgentToolInputSchema { .object(properties: [:], required: []) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let xml = try await runtime.exportOPML(runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: xml)
    }
}

public struct RSSCreateEvidenceCandidateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_create_evidence_candidate" }
    public var description: String { "Create a governed Graph Memory evidence candidate from an RSS item without direct graph write." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["itemID": .string(description: "RSS item ID")], required: ["itemID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let itemID = arguments.string("itemID") else { throw AgentToolError.invalidArguments("itemID is required") }
        let candidate = try await runtime.evidenceCandidate(for: RSSItemID(rawValue: itemID))
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Created RSS evidence candidate for \(itemID)", contentJSON: try RSSJSON.encode(candidate))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeRSSTools(runtime: any AgentRSSRuntime) {
        register(RSSListSourcesTool(runtime: runtime))
        register(RSSAddSourceTool(runtime: runtime))
        register(RSSSyncSourceTool(runtime: runtime))
        register(RSSListItemsTool(runtime: runtime))
        register(RSSSearchItemsTool(runtime: runtime))
        register(RSSGetItemTool(runtime: runtime))
        register(RSSSetReadStateTool(runtime: runtime))
        register(RSSSetStarStateTool(runtime: runtime))
        register(RSSSetHiddenStateTool(runtime: runtime))
        register(RSSCreateEvidenceCandidateTool(runtime: runtime))
    }
}
