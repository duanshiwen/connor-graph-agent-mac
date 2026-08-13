import Foundation
import ConnorGraphCore

public protocol AgentRSSRuntime: Sendable {
    func listSources(runID: String?, sessionID: String?) async throws -> [RSSSource]
    func addSource(feedURL: URL, displayName: String?, runID: String?, sessionID: String?) async throws -> RSSSource
    /// 更新既有源：feedURL 传 nil 表示保留当前地址；displayName 传 nil 表示保留当前名称，传空串表示重置为 feed 主机名。
    func updateSource(sourceID: RSSSourceID, feedURL: URL?, displayName: String?, runID: String?, sessionID: String?) async throws -> RSSSource
    /// 删除既有源：本地删除并记录待回推 tombstone，同时清空其缓存条目。
    func deleteSource(sourceID: RSSSourceID, runID: String?, sessionID: String?) async throws
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
    private static func encodedObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private static func string(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func addingItemID(to object: inout [String: Any]) {
        if let id = object["id"] { object["itemID"] = id }
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        try string(encodedObject(value))
    }

    static func encodeSources(_ sources: [RSSSource]) throws -> String {
        var rows = (try encodedObject(sources) as? [[String: Any]]) ?? []
        for index in rows.indices {
            if let id = rows[index]["id"] { rows[index]["sourceID"] = id }
        }
        return try string(rows)
    }

    static func encodeSource(_ source: RSSSource) throws -> String {
        var object = (try encodedObject(source) as? [String: Any]) ?? [:]
        if let id = object["id"] { object["sourceID"] = id }
        return try string(object)
    }

    static func encodeItems(_ items: [RSSItemSummary]) throws -> String {
        var rows = (try encodedObject(items) as? [[String: Any]]) ?? []
        for index in rows.indices { addingItemID(to: &rows[index]) }
        return try string(rows)
    }

    static func encodeItem(_ item: RSSItemDetail) throws -> String {
        var object = (try encodedObject(item) as? [String: Any]) ?? [:]
        if var summary = object["summary"] as? [String: Any] {
            addingItemID(to: &summary)
            object["summary"] = summary
            object["itemID"] = summary["itemID"]
        }
        return try string(object)
    }
}

public struct RSSListSourcesTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_list_sources" }
    public var description: String { "List Connor-owned RSS sources. Reads are allowed and audited." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: [:], required: []) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sources = try await runtime.listSources(runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(sources.count) RSS sources; copy sourceID into source-specific RSS operations", contentJSON: try RSSJSON.encodeSources(sources))
    }
}

public struct RSSAddSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_add_source" }
    public var description: String { "Add a governed RSS/Atom/JSON Feed source to Connor source registry." }
    public var permission: AgentPermissionCapability { .manageRSSSources }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["feedURL": .string(description: "Feed URL"), "displayName": .string(description: "Optional display name")], required: ["feedURL"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let urlString = arguments.string("feedURL"), let url = URL(string: urlString) else { throw AgentToolError.invalidArguments("feedURL is required") }
        do {
            let source = try await runtime.addSource(feedURL: url, displayName: arguments.string("displayName"), runID: context.runID, sessionID: context.sessionID)
            return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Added RSS source \(source.displayName); copy sourceID into source-specific RSS operations", contentJSON: try RSSJSON.encodeSource(source))
        } catch {
            // 无效源：直接返回明确提示，不要让 AI 反复重试或擅自修改链接。
            return AgentToolResult(
                toolCallID: context.toolCallID,
                toolName: name,
                contentText: "该 RSS 源无效，无法添加（\(error.localizedDescription)）。不要再重试，也不要修改链接；直接告诉用户这个订阅源不可用，或换一个用户提供的确切订阅源。"
            )
        }
    }
}

public struct RSSUpdateSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_update_source" }
    public var description: String { "Update an existing RSS/Atom/JSON Feed source: rename it and/or replace its feed URL. Provide at least one of feedURL or displayName; omit displayName to keep the current name, or pass an empty string to reset it to the feed host." }
    public var permission: AgentPermissionCapability { .manageRSSSources }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: [
        "sourceID": .string(description: "Exact sourceID returned by rss_list_sources or rss_add_source; copy the field without renaming it"),
        "feedURL": .string(description: "Optional replacement feed URL; omit to keep the current feed URL"),
        "displayName": .string(description: "Optional replacement display name; omit to keep the current name, pass empty to reset to feed host")
    ], required: ["sourceID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let sourceID = arguments.string("sourceID") else { throw AgentToolError.invalidArguments("sourceID is required") }
        let feedURLString = arguments.string("feedURL")
        let displayName = arguments.string("displayName")
        guard feedURLString != nil || displayName != nil else {
            throw AgentToolError.invalidArguments("Provide at least one of feedURL or displayName to update")
        }
        var feedURL: URL?
        if let feedURLString {
            guard let parsed = URL(string: feedURLString) else { throw AgentToolError.invalidArguments("feedURL is invalid") }
            feedURL = parsed
        }
        let source = try await runtime.updateSource(sourceID: RSSSourceID(rawValue: sourceID), feedURL: feedURL, displayName: displayName, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Updated RSS source \(source.displayName); copy sourceID into source-specific RSS operations", contentJSON: try RSSJSON.encodeSource(source))
    }
}

public struct RSSRemoveSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_remove_source" }
    public var description: String { "Remove an existing RSS/Atom/JSON Feed source from Connor source registry. Deleting a source also deletes its cached items." }
    public var permission: AgentPermissionCapability { .manageRSSSources }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: [
        "sourceID": .string(description: "Exact sourceID returned by rss_list_sources or rss_add_source; copy the field without renaming it")
    ], required: ["sourceID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let sourceID = arguments.string("sourceID") else { throw AgentToolError.invalidArguments("sourceID is required") }
        try await runtime.deleteSource(sourceID: RSSSourceID(rawValue: sourceID), runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Removed RSS source \(sourceID)", contentJSON: "{\"success\":true,\"sourceID\":\"\(sourceID)\"}")
    }
}

public struct RSSSyncSourceTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_sync_source" }
    public var description: String { "Synchronize an existing RSS source through Connor runtime." }
    public var permission: AgentPermissionCapability { .syncRSSSources }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["sourceID": .string(description: "Exact sourceID returned by rss_list_sources or rss_add_source; copy the field without renaming it")], required: ["sourceID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let sourceID = arguments.string("sourceID") else { throw AgentToolError.invalidArguments("sourceID is required") }
        let result = try await runtime.syncSource(sourceID: RSSSourceID(rawValue: sourceID), runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Synced RSS source; inserted \(result.insertedCount), duplicates \(result.duplicateCount)", contentJSON: try RSSJSON.encode(result))
    }
}

public struct RSSListItemsTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "rss_list_items" }
    public var description: String { "List RSS item summaries without reading full content." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["sourceID": .string(description: "Optional exact sourceID returned by rss_list_sources"), "includeHidden": .boolean(description: "Include hidden items"), "limit": .integer(description: "Maximum items")], required: []) }
    public init(runtime: any AgentRSSRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let items = try await runtime.listItems(sourceID: arguments.string("sourceID").map(RSSSourceID.init(rawValue:)), includeHidden: arguments.bool("includeHidden") ?? false, limit: NativeSearchLimitPolicy.clampListLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultListLimit), runID: context.runID, sessionID: context.sessionID)
        await recorder?.record(items.map { NativeSourceReference.rssSummary($0, query: nil, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(items.count) RSS item summaries; copy itemID into RSS item operations", contentJSON: try RSSJSON.encodeItems(items))
    }
}

public struct RSSSearchItemsTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "rss_search_items" }
    public var description: String { "Search Connor-owned RSS item summaries using indexed, time-aware retrieval by title, snippet, author, content, or source. Supports optional ISO-8601 startDate/endDate or timePreset; results include published/fetched time." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["query": .string(description: "Search query"), "sourceID": .string(description: "Optional exact sourceID returned by rss_list_sources"), "includeHidden": .boolean(description: "Include hidden"), "limit": .integer(description: "Maximum summaries"), "startDate": .string(description: "Optional ISO-8601 inclusive start timestamp for published/fetched time filtering"), "endDate": .string(description: "Optional ISO-8601 exclusive end timestamp for published/fetched time filtering"), "timePreset": .stringEnumeration(values: NativeSearchTimePreset.allCases.map(\.rawValue), description: "Optional relative time range."), "timeSort": .stringEnumeration(values: NativeSearchTemporalSort.allCases.map(\.rawValue), description: "Optional temporal result ordering.")], required: ["query"]) }
    public init(runtime: any AgentRSSRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let request = RSSRuntimeSearchRequestBridge(
            query: arguments.string("query") ?? "",
            sourceID: arguments.string("sourceID").map(RSSSourceID.init(rawValue:)),
            includeHidden: arguments.bool("includeHidden") ?? false,
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultListLimit),
            startDate: try arguments.iso8601Date("startDate"),
            endDate: try arguments.iso8601Date("endDate"),
            timePreset: arguments.string("timePreset"),
            timeSort: arguments.string("timeSort")
        )
        let items = try await runtime.searchItems(request, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record(items.map { NativeSourceReference.rssSummary($0, query: request.query, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(items.count) RSS item summaries; copy itemID into RSS item operations", contentJSON: try RSSJSON.encodeItems(items))
    }
}

public struct RSSGetItemTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "rss_get_item" }
    public var description: String { "Get RSS item detail; content is optional and audited separately." }
    public var permission: AgentPermissionCapability { .readRSSContent }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["itemID": .string(description: "Exact itemID returned by rss_list_items or rss_search_items; copy the field without renaming it"), "includeContent": .boolean(description: "Include full safe content")], required: ["itemID"]) }
    public init(runtime: any AgentRSSRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let itemID = arguments.string("itemID") else { throw AgentToolError.invalidArguments("itemID is required") }
        let includeContent = arguments.bool("includeContent") ?? false
        let item = try await runtime.getItem(id: RSSItemID(rawValue: itemID), includeContent: includeContent, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record([NativeSourceReference.rssDetail(item, includeContent: includeContent, toolName: name, context: context)])
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: includeContent ? "Read RSS item content" : "Read RSS item without content", contentJSON: try RSSJSON.encodeItem(item))
    }
}

public struct RSSSetReadStateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_set_read_state" }
    public var description: String { "Explicitly mutate RSS read/unread state." }
    public var permission: AgentPermissionCapability { .mutateRSSState }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["itemIDs": .array(items: .string(description: "Exact itemID returned by an RSS list/search result"), description: "Exact itemID values returned by RSS list/search results"), "isRead": .boolean(description: "Desired read state")], required: ["itemIDs", "isRead"]) }
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
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["itemIDs": .array(items: .string(description: "Exact itemID returned by an RSS list/search result"), description: "Exact itemID values returned by RSS list/search results"), "isStarred": .boolean(description: "Desired star state")], required: ["itemIDs", "isStarred"]) }
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
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["itemIDs": .array(items: .string(description: "Exact itemID returned by an RSS list/search result"), description: "Exact itemID values returned by RSS list/search results"), "isHidden": .boolean(description: "Desired hidden state")], required: ["itemIDs", "isHidden"]) }
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
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["opmlXML": .string(description: "OPML XML content")], required: ["opmlXML"]) }
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
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: [:], required: []) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let xml = try await runtime.exportOPML(runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: xml)
    }
}

public struct RSSCreateEvidenceCandidateTool: AgentTool {
    public let runtime: any AgentRSSRuntime
    public var name: String { "rss_create_evidence_candidate" }
    public var description: String { "Create a governed Memory OS evidence candidate from an RSS item without direct memory projection." }
    public var permission: AgentPermissionCapability { .readRSS }
    public var inputSchema: AgentToolInputSchema { .closedObject(properties: ["itemID": .string(description: "Exact itemID returned by rss_list_items or rss_search_items")], required: ["itemID"]) }
    public init(runtime: any AgentRSSRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let itemID = arguments.string("itemID") else { throw AgentToolError.invalidArguments("itemID is required") }
        let candidate = try await runtime.evidenceCandidate(for: RSSItemID(rawValue: itemID))
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Created RSS evidence candidate for \(itemID)", contentJSON: try RSSJSON.encode(candidate))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeRSSTools(runtime: any AgentRSSRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        register(RSSListSourcesTool(runtime: runtime))
        register(RSSAddSourceTool(runtime: runtime))
        register(RSSUpdateSourceTool(runtime: runtime))
        register(RSSRemoveSourceTool(runtime: runtime))
        register(RSSSyncSourceTool(runtime: runtime))
        register(RSSListItemsTool(runtime: runtime, recorder: recorder))
        register(RSSSearchItemsTool(runtime: runtime, recorder: recorder))
        register(RSSGetItemTool(runtime: runtime, recorder: recorder))
        register(RSSSetReadStateTool(runtime: runtime))
        register(RSSSetStarStateTool(runtime: runtime))
        register(RSSSetHiddenStateTool(runtime: runtime))
        register(RSSCreateEvidenceCandidateTool(runtime: runtime))
    }
}
