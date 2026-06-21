import Foundation
import ConnorGraphCore

public protocol AgentMailRuntime: Sendable {
    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount]
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary]
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws
    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], subject: String, body: String, runID: String?, sessionID: String?) async throws -> MailDraft
    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt
}

public struct MailRuntimeSearchRequestBridge: Sendable, Equatable {
    public var query: String
    public var accountID: MailAccountID?
    public var limit: Int
    public var startDate: Date?
    public var endDate: Date?
    public var timePreset: String?
    public var timeSort: String?

    public init(query: String, accountID: MailAccountID? = nil, limit: Int = 20, startDate: Date? = nil, endDate: Date? = nil, timePreset: String? = nil, timeSort: String? = nil) {
        self.query = query
        self.accountID = accountID
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        self.startDate = startDate
        self.endDate = endDate
        self.timePreset = timePreset
        self.timeSort = timeSort
    }
}

public struct MailSendApprovalBridge: Codable, Sendable, Equatable {
    public var draftID: MailDraftID
    public var title: String
    public var from: String
    public var to: [String]
    public var subject: String
    public var bodyPreview: String
    public var riskSummary: String
    public init(draftID: MailDraftID, title: String, from: String, to: [String], subject: String, bodyPreview: String, riskSummary: String) {
        self.draftID = draftID
        self.title = title
        self.from = from
        self.to = to
        self.subject = subject
        self.bodyPreview = bodyPreview
        self.riskSummary = riskSummary
    }
}

enum MailJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

public struct MailListAccountsTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_list_accounts" }
    public var description: String { "List Connor-owned mail accounts. Built-in mail reads are allowed and audited." }
    public var permission: AgentPermissionCapability { .readMail }
    public var inputSchema: AgentToolInputSchema { .object(properties: [:], required: []) }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let accounts = try await runtime.listAccounts(runID: context.runID, sessionID: context.sessionID)
        let json = try MailJSON.encode(accounts)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(accounts.count) mail accounts", contentJSON: json)
    }
}

public struct MailSearchMessagesTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_search_messages" }
    public var description: String { "Search Connor-owned mail summaries using indexed, time-aware retrieval without marking messages as read. Supports optional ISO-8601 startDate/endDate or timePreset; results include message date/time." }
    public var permission: AgentPermissionCapability { .readMail }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "query": .string(description: "Search query"),
            "accountID": .string(description: "Optional account ID"),
            "limit": .integer(description: "Maximum summaries"),
            "startDate": .string(description: "Optional ISO-8601 inclusive start timestamp for sent/received time filtering"),
            "endDate": .string(description: "Optional ISO-8601 exclusive end timestamp for sent/received time filtering"),
            "timePreset": .string(description: "Optional time preset such as today, last7Days, last30Days, thisWeek, lastMonth"),
            "timeSort": .string(description: "Optional sort: relevanceThenTimeDesc, relevanceThenTimeAsc, timeDescThenRelevance, timeAscThenRelevance")
        ], required: ["query"])
    }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let formatter = ISO8601DateFormatter()
        let request = MailRuntimeSearchRequestBridge(
            query: arguments.string("query") ?? "",
            accountID: arguments.string("accountID").map(MailAccountID.init(rawValue:)),
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit),
            startDate: arguments.string("startDate").flatMap { formatter.date(from: $0) },
            endDate: arguments.string("endDate").flatMap { formatter.date(from: $0) },
            timePreset: arguments.string("timePreset"),
            timeSort: arguments.string("timeSort")
        )
        let messages = try await runtime.searchMessages(request, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(messages.count) mail message summaries; read state unchanged", contentJSON: try MailJSON.encode(messages))
    }
}

public struct MailGetMessageTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_get_message" }
    public var description: String { "Get a mail message; body is optional and read state is never mutated by default." }
    public var permission: AgentPermissionCapability { .readMailBody }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "messageID": .string(description: "Message ID"),
            "includeBody": .boolean(description: "Whether to include body")
        ], required: ["messageID"])
    }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let messageID = arguments.string("messageID") else { throw AgentToolError.invalidArguments("messageID is required") }
        let includeBody = arguments.bool("includeBody") ?? false
        let detail = try await runtime.getMessage(id: MailMessageID(rawValue: messageID), includeBody: includeBody, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: includeBody ? "Read message body; read state unchanged" : "Read message without body; read state unchanged", contentJSON: try MailJSON.encode(detail))
    }
}

public struct MailSetReadStateTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_set_read_state" }
    public var description: String { "Explicitly mutate read/unread state for messages." }
    public var permission: AgentPermissionCapability { .mutateMailState }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "messageIDs": .array(items: .string(description: "Message ID"), description: "Message IDs"),
            "isRead": .boolean(description: "Desired read state")
        ], required: ["messageIDs", "isRead"])
    }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let ids = (arguments.array("messageIDs") ?? []).compactMap(\.stringValue).map(MailMessageID.init(rawValue:))
        let isRead = arguments.bool("isRead") ?? false
        try await runtime.setReadState(messageIDs: ids, isRead: isRead, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Updated read state for \(ids.count) messages")
    }
}

public struct MailCreateDraftTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_create_draft" }
    public var description: String { "Create a governed mail draft without sending." }
    public var permission: AgentPermissionCapability { .createMailDraft }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "accountID": .string(description: "Account ID"),
            "identityID": .string(description: "Identity ID"),
            "to": .array(items: .string(description: "Email address"), description: "Recipients"),
            "subject": .string(description: "Subject"),
            "body": .string(description: "Body")
        ], required: ["accountID", "identityID", "to", "subject", "body"])
    }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let accountID = arguments.string("accountID"), let identityID = arguments.string("identityID") else { throw AgentToolError.invalidArguments("accountID and identityID are required") }
        let to = (arguments.array("to") ?? []).compactMap(\.stringValue).map { MailAddress(email: $0) }
        let draft = try await runtime.createDraft(accountID: MailAccountID(rawValue: accountID), identityID: MailIdentityID(rawValue: identityID), to: to, subject: arguments.string("subject") ?? "", body: arguments.string("body") ?? "", runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Created draft \(draft.id.rawValue); not sent", contentJSON: try MailJSON.encode(draft))
    }
}

public struct MailSendDraftTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_send_draft" }
    public var description: String { "Send a draft only after explicit user approval. This tool is never auto-approved." }
    public var permission: AgentPermissionCapability { .sendMail }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["draftID": .string(description: "Draft ID"), "approved": .boolean(description: "Explicit approval flag")], required: ["draftID", "approved"]) }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let draftID = arguments.string("draftID") else { throw AgentToolError.invalidArguments("draftID is required") }
        let receipt = try await runtime.sendDraft(draftID: MailDraftID(rawValue: draftID), approved: arguments.bool("approved") ?? false, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Sent approved draft \(draftID)", contentJSON: try MailJSON.encode(receipt))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeMailTools(runtime: any AgentMailRuntime) {
        register(MailListAccountsTool(runtime: runtime))
        register(MailGetMessageTool(runtime: runtime))
        register(MailSetReadStateTool(runtime: runtime))
        register(MailCreateDraftTool(runtime: runtime))
        register(MailSendDraftTool(runtime: runtime))
    }
}
