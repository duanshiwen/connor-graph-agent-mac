import Foundation
import ConnorGraphCore

public struct MailSendPreferencesBridge: Codable, Sendable, Equatable {
    public var defaultSendAccountID: MailAccountID?
    public var defaultSendIdentityID: MailIdentityID?

    public init(defaultSendAccountID: MailAccountID? = nil, defaultSendIdentityID: MailIdentityID? = nil) {
        self.defaultSendAccountID = defaultSendAccountID
        self.defaultSendIdentityID = defaultSendIdentityID
    }
}

public protocol AgentMailRuntime: Sendable {
    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount]
    func loadMailPreferences(runID: String?, sessionID: String?) async throws -> MailSendPreferencesBridge
    func saveMailPreferences(_ preferences: MailSendPreferencesBridge, runID: String?, sessionID: String?) async throws
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary]
    func searchMessagesWithBodyPreview(_ request: MailRuntimeSearchRequestBridge, bodyPreviewMaxChars: Int, runID: String?, sessionID: String?) async throws -> [MailMessageBodyPreviewResult]
    func listRecentMessages(_ request: MailRuntimeRecentMessagesRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary]
    func listRecentMessagesWithBodyPreview(_ request: MailRuntimeRecentMessagesRequestBridge, bodyPreviewMaxChars: Int, runID: String?, sessionID: String?) async throws -> [MailMessageBodyPreviewResult]
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws
    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress], bcc: [MailAddress], replyTo: [MailAddress], subject: String, body: String, htmlBody: String?, inReplyToMessageID: MailMessageID?, attachmentIDs: [MailAttachmentID], intentSummary: String?, runID: String?, sessionID: String?) async throws -> MailDraft
    func sendApprovalBridgePayload(draftID: MailDraftID) async throws -> MailSendApprovalBridge
    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt
}

public extension AgentMailRuntime {
    func listRecentMessages(_ request: MailRuntimeRecentMessagesRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] {
        try await searchMessages(
            MailRuntimeSearchRequestBridge(query: "", accountID: request.accountID, limit: request.limit, timeSort: "timeDescThenRelevance"),
            runID: runID,
            sessionID: sessionID
        )
    }

    func loadMailPreferences(runID: String?, sessionID: String?) async throws -> MailSendPreferencesBridge { MailSendPreferencesBridge() }

    func saveMailPreferences(_ preferences: MailSendPreferencesBridge, runID: String?, sessionID: String?) async throws {}

    func searchMessagesWithBodyPreview(_ request: MailRuntimeSearchRequestBridge, bodyPreviewMaxChars: Int, runID: String?, sessionID: String?) async throws -> [MailMessageBodyPreviewResult] {
        throw AgentToolError.invalidArguments("mail_search_messages_with_body_preview is not supported by this mail runtime")
    }

    func listRecentMessagesWithBodyPreview(_ request: MailRuntimeRecentMessagesRequestBridge, bodyPreviewMaxChars: Int, runID: String?, sessionID: String?) async throws -> [MailMessageBodyPreviewResult] {
        throw AgentToolError.invalidArguments("mail_list_recent_messages_with_body_preview is not supported by this mail runtime")
    }

    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress], bcc: [MailAddress], replyTo: [MailAddress], subject: String, body: String, htmlBody: String?, inReplyToMessageID: MailMessageID?, attachmentIDs: [MailAttachmentID], intentSummary: String?, runID: String?, sessionID: String?) async throws -> MailDraft {
        MailDraft(id: MailDraftID(rawValue: UUID().uuidString), accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, subject: subject, body: body, htmlBody: htmlBody, replyTo: replyTo, attachmentIDs: attachmentIDs, inReplyToMessageID: inReplyToMessageID, intentSummary: intentSummary)
    }

    func sendApprovalBridgePayload(draftID: MailDraftID) async throws -> MailSendApprovalBridge {
        MailSendApprovalBridge(draftID: draftID, title: "Send email approval", from: "unknown", to: [], cc: [], bcc: [], subject: "", bodyPreview: "", attachmentCount: 0, riskSummary: "Email sending is always approval-gated.", envelopeHash: "")
    }
}

public enum AgentMailMessageDirectionFilter: String, Sendable, Codable, Equatable, CaseIterable {
    case all
    case received
    case sent
}

public struct MailRuntimeRecentMessagesRequestBridge: Sendable, Equatable {
    public var accountID: MailAccountID?
    public var direction: AgentMailMessageDirectionFilter
    public var limit: Int

    public init(accountID: MailAccountID? = nil, direction: AgentMailMessageDirectionFilter = .all, limit: Int = NativeSearchLimitPolicy.defaultSearchLimit) {
        self.accountID = accountID
        self.direction = direction
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
    }
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
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var bodyPreview: String
    public var attachmentCount: Int
    public var riskSummary: String
    public var envelopeHash: String
    public init(draftID: MailDraftID, title: String, from: String, to: [String], cc: [String] = [], bcc: [String] = [], subject: String, bodyPreview: String, attachmentCount: Int = 0, riskSummary: String, envelopeHash: String = "") {
        self.draftID = draftID
        self.title = title
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyPreview = bodyPreview
        self.attachmentCount = attachmentCount
        self.riskSummary = riskSummary
        self.envelopeHash = envelopeHash
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
    public let recorder: (any NativeSourceReferenceRecording)?
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
    public init(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
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
        await recorder?.record(messages.map { NativeSourceReference.mailSummary($0, query: request.query, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(messages.count) mail message summaries; use the selected summary's id as messageID for mail_get_message; read state unchanged", contentJSON: try MailJSON.encode(messages))
    }
}

public struct MailListRecentMessagesTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "mail_list_recent_messages" }
    public var description: String { "List recent Connor-owned mail summaries across all accounts by newest sent/received time, without reading bodies or mutating read state. Supports optional account and direction filters." }
    public var permission: AgentPermissionCapability { .readMail }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "accountID": .string(description: "Optional exact MailAccount.id from mail_list_accounts; omit to search all mail accounts"),
            "direction": .string(description: "Optional direction filter: all, received, or sent. Defaults to all, mixing received and sent mail by newest time."),
            "limit": .integer(description: "Maximum recent mail summaries to return")
        ], required: [])
    }
    public init(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let direction: AgentMailMessageDirectionFilter
        if let rawDirection = arguments.string("direction") {
            guard let parsed = AgentMailMessageDirectionFilter(rawValue: rawDirection) else {
                throw AgentToolError.invalidArguments("Invalid direction \"\(rawDirection)\". Expected one of: all, received, sent.")
            }
            direction = parsed
        } else {
            direction = .all
        }
        let request = MailRuntimeRecentMessagesRequestBridge(
            accountID: arguments.string("accountID").map(MailAccountID.init(rawValue:)),
            direction: direction,
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit)
        )
        let messages = try await runtime.listRecentMessages(request, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record(messages.map { NativeSourceReference.mailSummary($0, query: "recent", toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(messages.count) recent mail message summaries; use the selected summary's id as messageID for mail_get_message; read state unchanged", contentJSON: try MailJSON.encode(messages))
    }
}

private enum MailBodyPreviewToolPolicy {
    static let defaultMaxChars = 1200
    static let minMaxChars = 200
    static let maxMaxChars = 2_000

    static func clampedMaxChars(from arguments: AgentToolArguments) -> Int {
        let raw = arguments.int("bodyPreviewMaxChars") ?? defaultMaxChars
        return min(max(raw, minMaxChars), maxMaxChars)
    }
}

public struct MailSearchMessagesWithBodyPreviewTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "mail_search_messages_with_body_preview" }
    public var description: String { "Search Connor-owned mail and return bounded cached body previews for each result without mutating read state. Requires mail body read permission." }
    public var permission: AgentPermissionCapability { .readMailBody }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "query": .string(description: "Search query; cached body text is included in search where available"),
            "accountID": .string(description: "Optional account ID"),
            "limit": .integer(description: "Maximum results"),
            "startDate": .string(description: "Optional ISO-8601 inclusive start timestamp for sent/received time filtering"),
            "endDate": .string(description: "Optional ISO-8601 exclusive end timestamp for sent/received time filtering"),
            "timePreset": .string(description: "Optional time preset such as today, last7Days, last30Days, thisWeek, lastMonth"),
            "timeSort": .string(description: "Optional sort: relevanceThenTimeDesc, relevanceThenTimeAsc, timeDescThenRelevance, timeAscThenRelevance"),
            "bodyPreviewMaxChars": .integer(description: "Maximum cached body preview characters per message; clamped between 200 and 2000; defaults to 1200")
        ], required: ["query"])
    }
    public init(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
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
        let maxChars = MailBodyPreviewToolPolicy.clampedMaxChars(from: arguments)
        let results = try await runtime.searchMessagesWithBodyPreview(request, bodyPreviewMaxChars: maxChars, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record(results.map { NativeSourceReference.mailSummary($0.summary, query: request.query, toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(results.count) mail messages with cached body previews up to \(maxChars) characters each; use summary.id as messageID for mail_get_message for full bodies; read state unchanged; missing previews were not fetched remotely", contentJSON: try MailJSON.encode(results))
    }
}

public struct MailListRecentMessagesWithBodyPreviewTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "mail_list_recent_messages_with_body_preview" }
    public var description: String { "List recent Connor-owned mail across accounts with bounded cached body previews, without mutating read state. Requires mail body read permission." }
    public var permission: AgentPermissionCapability { .readMailBody }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "accountID": .string(description: "Optional exact MailAccount.id from mail_list_accounts; omit to search all mail accounts"),
            "direction": .string(description: "Optional direction filter: all, received, or sent. Defaults to all, mixing received and sent mail by newest time."),
            "limit": .integer(description: "Maximum recent mail results to return"),
            "bodyPreviewMaxChars": .integer(description: "Maximum cached body preview characters per message; clamped between 200 and 2000; defaults to 1200")
        ], required: [])
    }
    public init(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let direction: AgentMailMessageDirectionFilter
        if let rawDirection = arguments.string("direction") {
            guard let parsed = AgentMailMessageDirectionFilter(rawValue: rawDirection) else {
                throw AgentToolError.invalidArguments("Invalid direction \"\(rawDirection)\". Expected one of: all, received, sent.")
            }
            direction = parsed
        } else {
            direction = .all
        }
        let request = MailRuntimeRecentMessagesRequestBridge(
            accountID: arguments.string("accountID").map(MailAccountID.init(rawValue:)),
            direction: direction,
            limit: NativeSearchLimitPolicy.clampSearchLimit(arguments.int("limit") ?? NativeSearchLimitPolicy.defaultSearchLimit)
        )
        let maxChars = MailBodyPreviewToolPolicy.clampedMaxChars(from: arguments)
        let results = try await runtime.listRecentMessagesWithBodyPreview(request, bodyPreviewMaxChars: maxChars, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record(results.map { NativeSourceReference.mailSummary($0.summary, query: "recent", toolName: name, context: context) })
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Found \(results.count) recent mail messages with cached body previews up to \(maxChars) characters each; use summary.id as messageID for mail_get_message for full bodies; read state unchanged; missing previews were not fetched remotely", contentJSON: try MailJSON.encode(results))
    }
}

public struct MailGetMessageTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public let recorder: (any NativeSourceReferenceRecording)?
    public var name: String { "mail_get_message" }
    public var description: String { "Get a mail message; body is optional and read state is never mutated by default." }
    public var permission: AgentPermissionCapability { .readMailBody }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "messageID": .string(description: "Exact MailMessageSummary.id returned by mail_search_messages or mail_list_recent_messages. Do not pass result numbers, invented pseudo IDs such as 'message1' or 'msg1', or IMAP UIDs."),
            "includeBody": .boolean(description: "Whether to include body")
        ], required: ["messageID"])
    }
    public init(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.runtime = runtime
        self.recorder = recorder
    }

    private static func guidanceForOrdinalLikeMessageID(_ value: String) -> AgentToolError {
        .invalidArguments("mail_get_message expects the exact messageID returned in a MailMessageSummary from mail_search_messages or mail_list_recent_messages. Received \"\(value)\", which looks like a result index or invented pseudo ID. Pass the selected summary's id field exactly; do not pass ordinals such as '1', pseudo IDs such as 'message1'/'msg1', or IMAP UIDs.")
    }

    private static func looksLikeOrdinalOrPseudoResultID(_ value: String) -> Bool {
        if value.allSatisfy(\.isNumber) { return true }
        let lowercased = value.lowercased()
        let pattern = #"^(message|msg|mail|email|result) ?[0-9]+$"#
        return lowercased.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedMessageID(from arguments: AgentToolArguments) throws -> String {
        guard let rawMessageID = arguments.string("messageID") else { throw AgentToolError.invalidArguments("messageID is required") }
        let messageID = rawMessageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageID.isEmpty else { throw AgentToolError.invalidArguments("messageID is required") }
        if looksLikeOrdinalOrPseudoResultID(messageID) {
            throw guidanceForOrdinalLikeMessageID(messageID)
        }
        return messageID
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let messageID = try Self.normalizedMessageID(from: arguments)
        let includeBody = arguments.bool("includeBody") ?? false
        let detail = try await runtime.getMessage(id: MailMessageID(rawValue: messageID), includeBody: includeBody, runID: context.runID, sessionID: context.sessionID)
        await recorder?.record([NativeSourceReference.mailDetail(detail, includeBody: includeBody, toolName: name, context: context)])
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
    public var description: String { "Create a governed mail draft without sending. The returned MailDraft.id is the exact draftID to pass to mail_send_draft when requesting the native send-approval card; never ask the user to provide this ID." }
    public var permission: AgentPermissionCapability { .createMailDraft }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "accountID": .string(description: "Optional exact MailAccount.id from mail_list_accounts. Omit, empty, or pass default to use the Settings default send account; never invent account IDs."),
            "identityID": .string(description: "Optional exact MailIdentity.id from the selected account. Omit, empty, or pass default to use the Settings default send identity; never invent identity IDs."),
            "to": .array(items: .string(description: "Email address"), description: "Recipients"),
            "cc": .array(items: .string(description: "Email address"), description: "CC recipients"),
            "bcc": .array(items: .string(description: "Email address"), description: "BCC recipients"),
            "replyTo": .array(items: .string(description: "Email address"), description: "Reply-To addresses"),
            "subject": .string(description: "Subject"),
            "body": .string(description: "Plain-text body"),
            "htmlBody": .string(description: "Optional HTML body"),
            "inReplyToMessageID": .string(description: "Optional source message ID for replies"),
            "attachmentIDs": .array(items: .string(description: "Attachment ID"), description: "Attachment IDs"),
            "intentSummary": .string(description: "Short user intent summary for auditing")
        ], required: ["to", "subject", "body"])
    }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    private static func addresses(_ values: [SendableJSONValue]?) -> [MailAddress] {
        (values ?? []).compactMap(\.stringValue).map { MailAddress(email: $0) }
    }

    private struct ResolvedSendIdentity: Sendable {
        var account: MailAccount
        var identity: MailIdentity
    }

    private static func normalizedOptionalID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.lowercased() == "default" ? nil : trimmed
    }

    private func resolveSendIdentity(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> ResolvedSendIdentity {
        let accounts = try await runtime.listAccounts(runID: context.runID, sessionID: context.sessionID)
        guard !accounts.isEmpty else {
            throw AgentToolError.invalidArguments("No mail accounts configured. Add a mail account in Settings before sending mail.")
        }
        let explicitAccountID = Self.normalizedOptionalID(arguments.string("accountID")).map(MailAccountID.init(rawValue:))
        let explicitIdentityID = Self.normalizedOptionalID(arguments.string("identityID")).map(MailIdentityID.init(rawValue:))

        let account: MailAccount
        if let explicitAccountID {
            guard let found = accounts.first(where: { $0.id == explicitAccountID }) else {
                let available = accounts.map(\.id.rawValue).joined(separator: ", ")
                throw AgentToolError.invalidArguments("Unknown mail account \"\(explicitAccountID.rawValue)\". Available account IDs: \(available). Use exact IDs from mail_list_accounts or omit accountID to use the Settings default send account.")
            }
            account = found
        } else {
            let preferences = try await runtime.loadMailPreferences(runID: context.runID, sessionID: context.sessionID)
            if let defaultAccountID = preferences.defaultSendAccountID,
               let found = accounts.first(where: { $0.id == defaultAccountID }) {
                account = found
            } else {
                let sendableAccounts = accounts.filter { $0.outgoing != nil && $0.identities.contains(where: \.canSend) }
                guard sendableAccounts.count == 1, let only = sendableAccounts.first else {
                    throw AgentToolError.invalidArguments("Multiple mail accounts are configured but no default send account is selected. Open Settings → Mail System → Send Settings and choose a default send account before creating a draft.")
                }
                let identity = only.identities.first(where: \.canSend)
                try await runtime.saveMailPreferences(MailSendPreferencesBridge(defaultSendAccountID: only.id, defaultSendIdentityID: identity?.id), runID: context.runID, sessionID: context.sessionID)
                account = only
            }
        }

        guard account.outgoing != nil else {
            throw AgentToolError.invalidArguments("Mail account \"\(account.id.rawValue)\" has no outgoing SMTP endpoint configured. Update the account in Settings before sending mail.")
        }

        let identity: MailIdentity
        if let explicitIdentityID {
            guard let found = account.identities.first(where: { $0.id == explicitIdentityID }) else {
                let available = account.identities.map(\.id.rawValue).joined(separator: ", ")
                throw AgentToolError.invalidArguments("Unknown mail identity \"\(explicitIdentityID.rawValue)\" for account \"\(account.id.rawValue)\". Available identity IDs: \(available).")
            }
            guard found.canSend else {
                throw AgentToolError.invalidArguments("Mail identity \"\(found.id.rawValue)\" cannot send mail.")
            }
            identity = found
        } else if let defaultIdentityID = try await runtime.loadMailPreferences(runID: context.runID, sessionID: context.sessionID).defaultSendIdentityID,
                  let found = account.identities.first(where: { $0.id == defaultIdentityID && $0.canSend }) {
            identity = found
        } else if let found = account.identities.first(where: \.canSend) {
            identity = found
        } else {
            throw AgentToolError.invalidArguments("Mail account \"\(account.id.rawValue)\" has no sendable identity. Update the account in Settings before sending mail.")
        }

        return ResolvedSendIdentity(account: account, identity: identity)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let resolved = try await resolveSendIdentity(arguments: arguments, context: context)
        let to = Self.addresses(arguments.array("to"))
        let cc = Self.addresses(arguments.array("cc"))
        let bcc = Self.addresses(arguments.array("bcc"))
        let replyTo = Self.addresses(arguments.array("replyTo"))
        let attachmentIDs = (arguments.array("attachmentIDs") ?? []).compactMap(\.stringValue).map(MailAttachmentID.init(rawValue:))
        let inReplyToMessageID = arguments.string("inReplyToMessageID").map(MailMessageID.init(rawValue:))
        let draft = try await runtime.createDraft(accountID: resolved.account.id, identityID: resolved.identity.id, to: to, cc: cc, bcc: bcc, replyTo: replyTo, subject: arguments.string("subject") ?? "", body: arguments.string("body") ?? "", htmlBody: arguments.string("htmlBody"), inReplyToMessageID: inReplyToMessageID, attachmentIDs: attachmentIDs, intentSummary: arguments.string("intentSummary"), runID: context.runID, sessionID: context.sessionID)
        let draftID = draft.id.rawValue
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Created draft \(draftID) using account=\"\(resolved.account.id.rawValue)\" from=\"\(resolved.identity.address.email)\"; not sent. To request the native Compose approval card for sending, call mail_send_draft with draftID=\"\(draftID)\". Do not ask the user to provide the draft ID.",
            contentJSON: try MailJSON.encode(draft)
        )
    }
}

public struct MailSendDraftTool: AgentTool {
    public let runtime: any AgentMailRuntime
    public var name: String { "mail_send_draft" }
    public var description: String { "Request native Compose approval to send an existing mail draft. Use the exact MailDraft.id returned by mail_create_draft; this tool is never auto-approved and must not be replaced with a natural-language confirmation." }
    public var permission: AgentPermissionCapability { .sendMail }
    public var inputSchema: AgentToolInputSchema { .object(properties: ["draftID": .string(description: "Exact MailDraft.id returned by mail_create_draft. Do not ask the user to provide this ID; pass the ID from the prior tool result to trigger the native Compose approval card.")], required: ["draftID"]) }
    public init(runtime: any AgentMailRuntime) { self.runtime = runtime }
    public func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        guard let args = try? AgentToolArguments(json: call.argumentsJSON), let draftID = args.string("draftID"), let payload = try? await runtime.sendApprovalBridgePayload(draftID: MailDraftID(rawValue: draftID)) else {
            return call.argumentsJSON
        }
        return (try? MailJSON.encode(payload)) ?? call.argumentsJSON
    }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let draftID = arguments.string("draftID") else { throw AgentToolError.invalidArguments("draftID is required") }
        let isHumanApproved = context.approvedCapabilities.contains(.sendMail)
        let receipt = try await runtime.sendDraft(draftID: MailDraftID(rawValue: draftID), approved: isHumanApproved, runID: context.runID, sessionID: context.sessionID)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Sent approved draft \(draftID)", contentJSON: try MailJSON.encode(receipt))
    }
}

public extension AgentToolRegistry {
    mutating func registerNativeMailTools(runtime: any AgentMailRuntime, recorder: (any NativeSourceReferenceRecording)? = nil) {
        register(MailListAccountsTool(runtime: runtime))
        register(MailSearchMessagesTool(runtime: runtime, recorder: recorder))
        register(MailSearchMessagesWithBodyPreviewTool(runtime: runtime, recorder: recorder))
        register(MailListRecentMessagesTool(runtime: runtime, recorder: recorder))
        register(MailListRecentMessagesWithBodyPreviewTool(runtime: runtime, recorder: recorder))
        register(MailGetMessageTool(runtime: runtime, recorder: recorder))
        register(MailSetReadStateTool(runtime: runtime))
        register(MailCreateDraftTool(runtime: runtime))
        register(MailSendDraftTool(runtime: runtime))
    }
}
