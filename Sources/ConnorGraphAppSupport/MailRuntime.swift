import Foundation
import ConnorGraphCore

public struct MailRuntimeRecentMessagesRequest: Sendable, Equatable {
    public var accountID: MailAccountID?
    public var direction: MailMessageDirectionFilter
    public var limit: Int

    public init(accountID: MailAccountID? = nil, direction: MailMessageDirectionFilter = .all, limit: Int = NativeSearchLimitPolicy.defaultSearchLimit) {
        self.accountID = accountID
        self.direction = direction
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
    }
}

public struct MailRuntimeSearchRequest: Sendable, Equatable {
    public var query: String
    public var accountID: MailAccountID?
    public var limit: Int
    public var startDate: Date?
    public var endDate: Date?
    public var timePreset: NativeSearchTimePreset?
    public var timeSort: NativeSearchTemporalSort

    public init(query: String, accountID: MailAccountID? = nil, limit: Int = 20, startDate: Date? = nil, endDate: Date? = nil, timePreset: NativeSearchTimePreset? = nil, timeSort: NativeSearchTemporalSort = .relevanceThenTimeDesc) {
        self.query = query
        self.accountID = accountID
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        self.startDate = startDate
        self.endDate = endDate
        self.timePreset = timePreset
        self.timeSort = timeSort
    }

    public var temporalFilter: NativeSearchTemporalFilter? {
        if let timePreset {
            var filter = NativeSearchTimePresetResolver.resolve(timePreset)
            filter.timeFieldPreference = [.sentAt, .receivedAt]
            return filter
        }
        return .sourceDefault(start: startDate, end: endDate, sourceKind: .mail)
    }
}


public struct MailRuntime: Sendable {
    public var repository: any MailSourceRepository
    public var cache: any MailSourceCache
    public var auditLog: any MailAuditLogProtocol
    public var draftStore: any MailDraftRepository
    public var credentialStore: AppMailCredentialStore
    public var preferencesStore: (any MailPreferencesStore)?
    public var smtpClient: any MailSMTPClient
    public var sentMessageRemoteAppender: any MailSentMessageRemoteAppender
    public var messageComposer: MailMessageComposer
    public var outboundAttachmentResolver: (any OutboundMailAttachmentResolving)?
    public var memoryOSFacade: AppMemoryOSFacade?

    public init(
        repository: any MailSourceRepository,
        cache: any MailSourceCache,
        auditLog: any MailAuditLogProtocol = InMemoryMailAuditLog(),
        draftStore: any MailDraftRepository = MailDraftStore(),
        credentialStore: AppMailCredentialStore = AppMailCredentialStore(),
        preferencesStore: (any MailPreferencesStore)? = nil,
        smtpClient: any MailSMTPClient = NetworkMailSMTPClient(),
        sentMessageRemoteAppender: any MailSentMessageRemoteAppender = NetworkMailSentMessageRemoteAppender(),
        messageComposer: MailMessageComposer = MailMessageComposer(),
        outboundAttachmentResolver: (any OutboundMailAttachmentResolving)? = nil,
        memoryOSFacade: AppMemoryOSFacade? = nil
    ) {
        self.repository = repository
        self.cache = cache
        self.auditLog = auditLog
        self.draftStore = draftStore
        self.credentialStore = credentialStore
        self.preferencesStore = preferencesStore
        self.smtpClient = smtpClient
        self.sentMessageRemoteAppender = sentMessageRemoteAppender
        self.messageComposer = messageComposer
        self.outboundAttachmentResolver = outboundAttachmentResolver
        self.memoryOSFacade = memoryOSFacade
    }

    public static func fixture() -> MailRuntime {
        let accountID = MailAccountID(rawValue: "fixture-account")
        let identity = MailIdentity(id: MailIdentityID(rawValue: "fixture-identity"), displayName: "Connor Fixture", address: MailAddress(name: "Connor Fixture", email: "connor@example.com"))
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: identity.address.email, authMode: .appPassword)
        let credentialStore = CommercialFixtureMailCredentialStore(secret: "fixture-password", binding: binding)
        let account = MailAccount(id: accountID, provider: .localFixture, displayName: "Fixture Mail", identities: [identity], outgoing: MailServerEndpoint(host: "smtp.fixture.local", port: 587, security: .startTLS, protocolKind: .smtp), credentialBinding: binding, health: MailAccountHealth(status: .ready, summary: "Fixture ready"))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "fixture-inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 1, unreadCount: 1, syncCursor: MailSyncCursor(value: "1"), lastSyncedAt: Date()))
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "fixture-message-1"),
            accountID: accountID,
            mailboxID: inbox.id,
            threadID: MailThreadID(rawValue: "fixture-thread-1"),
            subject: "Connor Native Mail System",
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [identity.address],
            snippet: "Commercial native mail system fixture",
            flags: MailMessageFlags(isRead: false),
            hasAttachments: true
        )
        let body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "Commercial native mail system fixture body", byteCount: 43), redactedPreview: "Commercial native mail system fixture body", bodyHash: "fixture-body-hash")
        let attachment = MailAttachmentDescriptor(id: MailAttachmentID(rawValue: "fixture-attachment-1"), messageID: summary.id, filename: "brief.pdf", mimeType: "application/pdf", byteCount: 1024)
        let detail = MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: "<fixture@example.com>", rawHeaderHash: "fixture-header-hash"), body: body, attachments: [attachment])
        return MailRuntime(repository: InMemoryMailSourceRepository(accounts: [account]), cache: InMemoryMailSourceCache(mailboxes: [inbox], messages: [detail]), credentialStore: AppMailCredentialStore(credentialStore: credentialStore), smtpClient: FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "fixture-smtp-message-id")))
    }

    public func listAccounts(runID: String? = nil, sessionID: String? = nil) async throws -> [MailAccount] {
        let accounts = try await repository.listAccounts()
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, kind: .accountHealthChecked, riskClass: .read, redactedSummary: "Listed \(accounts.count) mail accounts"))
        return accounts
    }

    public func accountHealth(accountID: MailAccountID, runID: String? = nil, sessionID: String? = nil) async throws -> MailAccountHealth {
        guard let account = try await repository.account(id: accountID) else { throw MailRuntimeError.accountNotFound(accountID.rawValue) }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, kind: .accountHealthChecked, riskClass: .read, redactedSummary: account.health.summary))
        return account.health
    }

    public func listMailboxes(accountID: MailAccountID, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMailbox] {
        let boxes = try await cache.listMailboxes(accountID: accountID)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Listed \(boxes.count) mailboxes"))
        return boxes
    }

    public func listRecentMessages(_ request: MailRuntimeRecentMessagesRequest, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(request.limit)
        let messages: [MailMessageSummary]
        if let recentCache = cache as? any RecentMailSourceCache {
            messages = try await recentCache.recentMessages(accountID: request.accountID, direction: request.direction, limit: limit)
        } else {
            let all = try await cache.searchMessages(query: "", accountID: request.accountID)
            let mailboxes = try await mailboxesForRecentMessages(accountID: request.accountID, messages: all)
            let byID = Dictionary(uniqueKeysWithValues: mailboxes.map { ($0.id, $0) })
            messages = all.filter { summary in
                switch request.direction {
                case .all:
                    return true
                case .received:
                    return byID[summary.mailboxID]?.role != .sent
                case .sent:
                    return byID[summary.mailboxID]?.role == .sent
                }
            }.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Listed recent mail messages; returned \(min(messages.count, limit)) summaries"))
        return Array(messages.prefix(limit))
    }

    public func searchMessages(_ request: MailRuntimeSearchRequest, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMessageSummary] {
        let messages: [MailMessageSummary]
        if let timeAwareCache = cache as? any TimeAwareMailSourceCache {
            messages = try await timeAwareCache.searchMessages(query: request.query, accountID: request.accountID, temporalFilter: request.temporalFilter, temporalSort: request.timeSort, limit: request.limit)
        } else {
            let all = try await cache.searchMessages(query: request.query, accountID: request.accountID)
            let filtered = request.temporalFilter.map { filter in all.filter { summary in
                filter.contains(NativeSearchTemporalMetadata(primaryTime: summary.date, primaryTimeKind: .sentAt, sentAt: summary.date), sourceKind: .mail)
            } } ?? all
            messages = filtered.sorted { lhs, rhs in request.timeSort == .timeAscThenRelevance || request.timeSort == .relevanceThenTimeAsc ? lhs.date < rhs.date : lhs.date > rhs.date }
        }
        let limit = NativeSearchLimitPolicy.clampSearchLimit(request.limit)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Searched mail messages; returned \(min(messages.count, limit)) summaries"))
        return Array(messages.prefix(limit))
    }

    public func listRecentMessagesWithBodyPreview(_ request: MailRuntimeRecentMessagesRequest, bodyPreviewMaxChars: Int, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMessageBodyPreviewResult] {
        let summaries = try await listRecentMessages(request, runID: runID, sessionID: sessionID)
        let results = try await bodyPreviewResults(for: summaries, maxChars: bodyPreviewMaxChars)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageBodyRead, riskClass: .bodyRead, redactedSummary: "Listed recent mail messages with cached body previews; returned \(results.count) previews without mutating read state"))
        return results
    }

    public func searchMessagesWithBodyPreview(_ request: MailRuntimeSearchRequest, bodyPreviewMaxChars: Int, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMessageBodyPreviewResult] {
        let summaries = try await searchMessages(request, runID: runID, sessionID: sessionID)
        let results = try await bodyPreviewResults(for: summaries, maxChars: bodyPreviewMaxChars)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageBodyRead, riskClass: .bodyRead, redactedSummary: "Searched mail messages with cached body previews; returned \(results.count) previews without mutating read state"))
        return results
    }

    private func bodyPreviewResults(for summaries: [MailMessageSummary], maxChars: Int) async throws -> [MailMessageBodyPreviewResult] {
        let maxChars = min(max(bodyPreviewMaxCharsLowerBound, maxChars), bodyPreviewMaxCharsUpperBound)
        var results: [MailMessageBodyPreviewResult] = []
        results.reserveCapacity(summaries.count)
        for summary in summaries {
            let detail = try await cache.message(id: summary.id)
            let preview = detail.flatMap { Self.bodyPreview(from: $0, maxChars: maxChars) }
            results.append(MailMessageBodyPreviewResult(summary: summary, bodyPreview: preview?.text, bodyPreviewTruncated: preview?.truncated ?? false, bodySource: preview?.source))
        }
        return results
    }

    private var bodyPreviewMaxCharsLowerBound: Int { 200 }
    private var bodyPreviewMaxCharsUpperBound: Int { 2_000 }

    private static func bodyPreview(from detail: MailMessageDetail, maxChars: Int) -> (text: String, truncated: Bool, source: String)? {
        let htmlPreview = (detail.body?.htmlText?.text).map { stripHTMLForPreview($0) }
        let candidates: [(String, String?)] = [
            ("plainText", detail.body?.plainText?.text),
            ("htmlText", htmlPreview),
            ("redactedPreview", detail.body?.redactedPreview)
        ]
        for (source, rawText) in candidates {
            let normalized = normalizeBodyPreviewText(rawText ?? "")
            guard !normalized.isEmpty else { continue }
            let truncated = normalized.count > maxChars
            return (String(normalized.prefix(maxChars)), truncated, source)
        }
        return nil
    }

    private static func normalizeBodyPreviewText(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHTMLForPreview(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private func mailboxesForRecentMessages(accountID: MailAccountID?, messages: [MailMessageSummary]) async throws -> [MailMailbox] {
        if let accountID {
            return try await cache.listMailboxes(accountID: accountID)
        }
        let accountIDs = Set(messages.map(\.accountID))
        let knownAccounts = try await repository.listAccounts().map(\.id)
        let allAccountIDs = Set(knownAccounts).union(accountIDs)
        var result: [MailMailbox] = []
        for id in allAccountIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(contentsOf: try await cache.listMailboxes(accountID: id))
        }
        return result
    }

    public func getMessage(id: MailMessageID, includeBody: Bool = false, runID: String? = nil, sessionID: String? = nil) async throws -> MailMessageDetail {
        guard var message = try await cache.message(id: id) else { throw MailRuntimeError.messageNotFound(id.rawValue) }
        if includeBody && !MailBodyOnDemandFetchPlanner.hasDisplayableBody(message) {
            // 本地缓存没有正文（列表同步通常只带摘要/简短 snippet）时，按需从服务器
            // 拉取完整正文并写回缓存，让 LLM 无需先在列表里点开邮件即可读到详情。
            if let fetched = try await fetchMessageBodyOnDemand(for: message) {
                message = fetched
                try await cache.saveMessage(fetched)
            }
        }
        if !includeBody { message.body = nil }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: message.summary.accountID, messageID: id, kind: includeBody ? .messageBodyRead : .messageRead, riskClass: includeBody ? .bodyRead : .read, redactedSummary: includeBody ? "Read mail body without mutating read state" : "Read mail summary/detail without body and without mutating read state", payloadHash: message.headers.rawHeaderHash))
        return message
    }

    /// 本地缓存缺少可显示正文时，按需从 IMAP 拉取完整消息；拉不到则返回 nil（保持缓存内容）。
    /// 使用消息所在真实邮箱解码 UID，覆盖 Inbox/Sent 之外的自定义文件夹。
    private func fetchMessageBodyOnDemand(for message: MailMessageDetail) async throws -> MailMessageDetail? {
        guard let account = try await repository.account(id: message.summary.accountID) else { return nil }
        let mailboxes = try await cache.listMailboxes(accountID: message.summary.accountID)
        let cachedMailbox = mailboxes.first { $0.id == message.summary.mailboxID }
        let remoteMailbox = RemoteIMAPMailbox(
            name: cachedMailbox?.name ?? "INBOX",
            path: cachedMailbox?.path ?? "INBOX",
            role: cachedMailbox?.role ?? .inbox
        )
        guard let uid = remoteMailbox.uid(fromMessageID: message.id, accountID: message.summary.accountID),
              uid.allSatisfy(\.isNumber) else { return nil }
        let service = MailIMAPInitialSyncService(credentialStore: credentialStore, messageLimit: 0)
        guard let fetched = try await service.fetchMessageBody(
            account: account,
            uid: uid,
            messageID: message.id,
            mailboxID: message.summary.mailboxID,
            mailboxPath: remoteMailbox.path,
            mailboxRole: remoteMailbox.role,
            snippet: message.summary.snippet
        ) else { return nil }
        guard MailBodyOnDemandFetchPlanner.hasDisplayableBody(fetched) else { return nil }
        return fetched
    }

    public func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String? = nil, sessionID: String? = nil) async throws {
        try await cache.updateFlags(messageIDs: messageIDs) { flags in
            var copy = flags
            copy.isRead = isRead
            return copy
        }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, kind: .stateMutated, riskClass: .mutation, redactedSummary: "Set read state for \(messageIDs.count) messages to \(isRead)"))
        NotificationCenter.default.post(
            name: .connorMailCacheDidChange,
            object: nil,
            userInfo: [
                MailCacheChangeNotificationUserInfoKey.messageIDs: messageIDs.map(\.rawValue),
                MailCacheChangeNotificationUserInfoKey.reason: MailCacheChangeReason.readStateUpdated.rawValue
            ]
        )
    }

    public func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress] = [], bcc: [MailAddress] = [], replyTo: [MailAddress] = [], subject: String, body: String, htmlBody: String? = nil, inReplyToMessageID: MailMessageID? = nil, attachmentIDs: [MailAttachmentID] = [], intentSummary: String? = nil, runID: String? = nil, sessionID: String? = nil) async throws -> MailDraft {
        try await persistDraft(
            accountID: accountID,
            identityID: identityID,
            to: to,
            cc: cc,
            bcc: bcc,
            replyTo: replyTo,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            inReplyToMessageID: inReplyToMessageID,
            attachmentIDs: attachmentIDs,
            intentSummary: intentSummary,
            runID: runID,
            sessionID: sessionID
        )
    }

    /// createDraft 的完整实现：校验账户/身份后落盘草稿，支持回复/转发所需的线程头。
    private func persistDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress] = [], bcc: [MailAddress] = [], replyTo: [MailAddress] = [], subject: String, body: String, htmlBody: String? = nil, inReplyToMessageID: MailMessageID? = nil, messageIDHeader: String? = nil, inReplyToHeader: String? = nil, referencesHeaders: [String] = [], attachmentIDs: [MailAttachmentID] = [], intentSummary: String? = nil, runID: String? = nil, sessionID: String? = nil) async throws -> MailDraft {
        guard let account = try await repository.account(id: accountID) else {
            throw MailRuntimeError.accountNotFound(accountID.rawValue)
        }
        guard let identity = account.identities.first(where: { $0.id == identityID }) else {
            throw MailRuntimeError.identityNotFound(identityID.rawValue)
        }
        guard identity.canSend else {
            throw MailRuntimeError.identityCannotSend(identityID.rawValue)
        }
        guard account.outgoing != nil else {
            throw MailRuntimeError.missingOutgoingEndpoint(accountID.rawValue)
        }
        let draft = MailDraft(id: MailDraftID(rawValue: UUID().uuidString), accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, subject: subject, body: body, htmlBody: htmlBody, replyTo: replyTo, attachmentIDs: attachmentIDs, inReplyToMessageID: inReplyToMessageID, messageIDHeader: messageIDHeader, inReplyToHeader: inReplyToHeader, referencesHeaders: referencesHeaders, intentSummary: intentSummary)
        try await draftStore.save(draft)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, draftID: draft.id, kind: .draftCreated, riskClass: .mutation, redactedSummary: "Created mail draft to \(to.map(\.email).joined(separator: ", "))"))
        return draft
    }

    /// 创建“回复”草稿：收件人自动取原发件人（原邮件为自己发送时取原收件人），
    /// 主题自动加 Re: 前缀，正文默认引用原邮件，并带上 In-Reply-To / References 线程头。
    public func createReplyDraft(accountID: MailAccountID, identityID: MailIdentityID, messageID: MailMessageID, body: String, includeOriginal: Bool = true, intentSummary: String? = nil, runID: String? = nil, sessionID: String? = nil) async throws -> MailDraft {
        let original = try await getMessage(id: messageID, includeBody: includeOriginal, runID: runID, sessionID: sessionID)
        guard let identity = try await repository.account(id: accountID)?.identities.first(where: { $0.id == identityID }) else {
            throw MailRuntimeError.identityNotFound(identityID.rawValue)
        }
        let recipients = Self.replyRecipients(for: original, selfEmail: identity.address.email)
        var subject = original.summary.subject
        if !Self.hasPrefix(subject, prefixes: ["Re:", "回复："]) {
            subject = "Re: " + subject
        }
        var bodyText = body
        if includeOriginal {
            bodyText += "\n\n" + Self.quotedOriginal(original)
        }
        var references = original.headers.references
        if let messageIDHeader = original.headers.messageIDHeader, !references.contains(messageIDHeader) {
            references.append(messageIDHeader)
        }
        return try await persistDraft(
            accountID: accountID,
            identityID: identityID,
            to: recipients,
            subject: subject,
            body: bodyText,
            inReplyToMessageID: messageID,
            inReplyToHeader: original.headers.messageIDHeader,
            referencesHeaders: references,
            intentSummary: intentSummary ?? "Reply to \(original.summary.subject)",
            runID: runID,
            sessionID: sessionID
        )
    }

    /// 创建“转发”草稿：主题自动加 Fwd: 前缀，正文默认附上原邮件（From/Date/To/Subject + 正文）。
    public func createForwardDraft(accountID: MailAccountID, identityID: MailIdentityID, messageID: MailMessageID, to: [MailAddress], cc: [MailAddress] = [], bcc: [MailAddress] = [], body: String, includeOriginal: Bool = true, intentSummary: String? = nil, runID: String? = nil, sessionID: String? = nil) async throws -> MailDraft {
        let original = try await getMessage(id: messageID, includeBody: includeOriginal, runID: runID, sessionID: sessionID)
        var subject = original.summary.subject
        if !Self.hasPrefix(subject, prefixes: ["Fwd:", "转发："]) {
            subject = "Fwd: " + subject
        }
        var bodyText = body
        if includeOriginal {
            bodyText += "\n\n" + Self.forwardedOriginal(original)
        }
        return try await persistDraft(
            accountID: accountID,
            identityID: identityID,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: bodyText,
            intentSummary: intentSummary ?? "Forward \(original.summary.subject)",
            runID: runID,
            sessionID: sessionID
        )
    }

    private static func replyRecipients(for original: MailMessageDetail, selfEmail: String) -> [MailAddress] {
        let sender = original.summary.from
        if sender.email.lowercased() == selfEmail.lowercased() {
            // 原邮件是自己发的（例如从 Sent 回复）→ 回给原始收件人，排除自己。
            return (original.summary.to + original.summary.cc).filter { $0.email.lowercased() != selfEmail.lowercased() }
        }
        return [sender]
    }

    private static func quotedOriginal(_ detail: MailMessageDetail) -> String {
        let sender = Self.formatAddress(detail.summary.from)
        let date = Self.mailQuoteDateFormatter.string(from: detail.summary.date)
        var lines = ["On \(date), \(sender) wrote:"]
        let body = detail.body?.plainText?.text ?? detail.body?.redactedPreview ?? ""
        for line in body.components(separatedBy: .newlines) where !line.isEmpty {
            lines.append("> " + line)
        }
        return lines.joined(separator: "\n")
    }

    private static func forwardedOriginal(_ detail: MailMessageDetail) -> String {
        var lines: [String] = []
        lines.append("-------- Forwarded Message --------")
        lines.append("From: \(Self.formatAddress(detail.summary.from))")
        lines.append("Date: \(Self.mailQuoteDateFormatter.string(from: detail.summary.date))")
        if !detail.summary.to.isEmpty {
            lines.append("To: \(detail.summary.to.map(Self.formatAddress).joined(separator: ", "))")
        }
        if !detail.summary.cc.isEmpty {
            lines.append("Cc: \(detail.summary.cc.map(Self.formatAddress).joined(separator: ", "))")
        }
        lines.append("Subject: \(detail.summary.subject)")
        lines.append("")
        let body = detail.body?.plainText?.text ?? detail.body?.redactedPreview ?? ""
        lines.append(body)
        return lines.joined(separator: "\n")
    }

    private static func formatAddress(_ address: MailAddress) -> String {
        if let name = address.name, !name.isEmpty {
            return "\(name) <\(address.email)>"
        }
        return address.email
    }

    private static func hasPrefix(_ subject: String, prefixes: [String]) -> Bool {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        return prefixes.contains { trimmed.hasPrefix($0) || trimmed.lowercased().hasPrefix($0.lowercased()) }
    }

    private static let mailQuoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public func sendApprovalPayload(draftID: MailDraftID) async throws -> MailRuntimeSendApproval {
        guard let draft = try await draftStore.draft(id: draftID) else { throw MailRuntimeError.draftNotFound(draftID.rawValue) }
        let account = try await repository.account(id: draft.accountID)
        let from = account?.identities.first { $0.id == draft.identityID }?.address.email ?? "unknown"
        let payload = MailRuntimeSendApproval(draft: draft, from: from)
        _ = try await draftStore.updateApprovedEnvelopeHash(id: draftID, envelopeHash: payload.envelopeHash)
        return payload
    }

    public func sendDraft(draftID: MailDraftID, approved: Bool, runID: String? = nil, sessionID: String? = nil) async throws -> MailSendReceipt {
        guard let draft = try await draftStore.draft(id: draftID) else { throw MailRuntimeError.draftNotFound(draftID.rawValue) }
        guard approved else {
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .sendApprovalRequested, riskClass: .send, redactedSummary: "Send approval required"))
            throw MailRuntimeError.approvalRequired(draftID.rawValue)
        }
        guard draft.status != .sent, draft.status != .discarded else {
            throw MailRuntimeError.invalidDraftState(draft.status.rawValue)
        }
        guard !draft.to.isEmpty || !draft.cc.isEmpty || !draft.bcc.isEmpty else {
            throw MailRuntimeError.missingRecipients(draftID.rawValue)
        }
        guard let account = try await repository.account(id: draft.accountID) else {
            throw MailRuntimeError.accountNotFound(draft.accountID.rawValue)
        }
        guard let identity = account.identities.first(where: { $0.id == draft.identityID }) else {
            throw MailRuntimeError.identityNotFound(draft.identityID.rawValue)
        }
        guard identity.canSend else {
            throw MailRuntimeError.identityCannotSend(draft.identityID.rawValue)
        }
        guard let endpoint = account.outgoing else {
            throw MailRuntimeError.missingOutgoingEndpoint(account.id.rawValue)
        }
        let attachments: [OutboundMailAttachment]
        if draft.attachmentIDs.isEmpty {
            attachments = []
        } else if let outboundAttachmentResolver {
            attachments = try await outboundAttachmentResolver.resolve(ids: draft.attachmentIDs, sessionID: sessionID)
        } else {
            throw MailRuntimeError.attachmentSessionRequired
        }
        let composed = try messageComposer.compose(draft: draft, identity: identity, attachments: attachments)
        guard let approvedEnvelopeHash = draft.approvedEnvelopeHash, !approvedEnvelopeHash.isEmpty else {
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .sendApprovalRequested, riskClass: .send, redactedSummary: "Approved send blocked because draft has no approved envelope hash", payloadHash: composed.envelopeHash))
            throw MailRuntimeError.missingApprovedEnvelopeHash(draftID.rawValue)
        }
        guard approvedEnvelopeHash == composed.envelopeHash else {
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .sendApprovalRequested, riskClass: .send, redactedSummary: "Approved send blocked because draft changed after approval", payloadHash: composed.envelopeHash))
            throw MailRuntimeError.envelopeHashMismatch(expected: approvedEnvelopeHash, actual: composed.envelopeHash)
        }
        guard let binding = account.credentialBinding else {
            throw MailRuntimeError.missingCredential(account.id.rawValue)
        }
        guard let password = try credentialStore.readCredential(binding: binding), !password.isEmpty else {
            throw MailRuntimeError.missingCredential(account.id.rawValue)
        }

        try await draftStore.recordSendAttempt(MailSendAttempt(draftID: draftID, status: .sending, envelopeHash: composed.envelopeHash))
        do {
            let response = try await smtpClient.send(MailSMTPSendRequest(
                endpoint: endpoint,
                username: Self.smtpAuthenticationUsername(from: binding.accountName, fallback: identity.address.email),
                password: password,
                from: identity.address,
                recipients: composed.envelopeRecipients,
                rawMessage: MailMessageComposer.dotStuff(composed.rawMessage),
                envelopeHash: composed.envelopeHash
            ))
            let receipt = MailSendReceipt(draftID: draftID, providerMessageID: response.providerMessageID, sentAt: response.sentAt, envelopeHash: composed.envelopeHash)
            try await draftStore.recordSendAttempt(MailSendAttempt(draftID: draftID, status: .sent, providerMessageID: response.providerMessageID, envelopeHash: composed.envelopeHash))
            _ = try await draftStore.updateStatus(id: draftID, status: .sent, sentReceiptID: receipt.providerMessageID)
            let sentMailbox = try await saveSentMessage(draft: draft, identity: identity, attachments: attachments, receipt: receipt, messageIDHeader: composed.messageID)
            await appendRemoteSentMessageIfPossible(account: account, password: password, draft: draft, receipt: receipt, rawMessage: composed.rawMessage, sentMailbox: sentMailbox, runID: runID, sessionID: sessionID)
            try captureOutboundMemoryEvidence(draft: draft, identity: identity, receipt: receipt, runID: runID, sessionID: sessionID)
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .messageSent, riskClass: .send, redactedSummary: "Sent authorized draft to \(draft.to.map(\.email).joined(separator: ", "))", payloadHash: receipt.envelopeHash))
            return receipt
        } catch {
            _ = try? await draftStore.updateStatus(id: draftID, status: .failed, lastSendError: String(describing: error))
            try? await draftStore.recordSendAttempt(MailSendAttempt(draftID: draftID, status: .failed, envelopeHash: composed.envelopeHash, errorSummary: String(describing: error)))
            throw error
        }
    }

    static func smtpAuthenticationUsername(from credentialAccountName: String, fallback: String) -> String {
        let trimmed = credentialAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if candidate.contains("@") {
            return candidate.lowercased()
        }
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? trimmed : fallback.lowercased()
    }

    public func sendHistory(draftID: MailDraftID) async throws -> MailSendHistory {
        guard let draft = try await draftStore.draft(id: draftID) else { throw MailRuntimeError.draftNotFound(draftID.rawValue) }
        let attempts = try await draftStore.sendAttempts(draftID: draftID)
        let auditRecords = try await auditLog.listRecords().filter { $0.draftID == draftID }
        return MailSendHistory(draft: draft, attempts: attempts, auditRecords: auditRecords)
    }

    private func saveSentMessage(draft: MailDraft, identity: MailIdentity, attachments: [OutboundMailAttachment], receipt: MailSendReceipt, messageIDHeader: String) async throws -> MailMailbox {
        let mailboxID = MailMailboxID(rawValue: "\(draft.accountID.rawValue)-sent")
        let existingMailboxes = try await cache.listMailboxes(accountID: draft.accountID)
        let sentMailbox: MailMailbox
        if let existingSentMailbox = existingMailboxes.first(where: { $0.role == .sent }) {
            sentMailbox = existingSentMailbox
        } else {
            sentMailbox = MailMailbox(
                id: mailboxID,
                accountID: draft.accountID,
                name: "Sent",
                path: "Sent",
                role: .sent,
                status: MailMailboxStatus(messageCount: 0, unreadCount: 0, lastSyncedAt: receipt.sentAt)
            )
            try await cache.saveMailbox(sentMailbox)
        }
        let messageID = MailMessageID(rawValue: receipt.providerMessageID)
        let summary = MailMessageSummary(
            id: messageID,
            accountID: draft.accountID,
            mailboxID: sentMailbox.id,
            threadID: draft.inReplyToMessageID.map { MailThreadID(rawValue: $0.rawValue) },
            subject: draft.subject,
            from: identity.address,
            to: draft.to,
            cc: draft.cc,
            date: receipt.sentAt,
            snippet: String(draft.body.prefix(240)),
            flags: MailMessageFlags(isRead: true),
            hasAttachments: !draft.attachmentIDs.isEmpty
        )
        let body = MailMessageBody(
            plainText: MailBodyPart(mimeType: "text/plain", text: draft.body, byteCount: Data(draft.body.utf8).count),
            htmlText: draft.htmlBody.map { MailBodyPart(mimeType: "text/html", text: $0, byteCount: Data($0.utf8).count) },
            redactedPreview: String(draft.body.prefix(500)),
            bodyHash: receipt.envelopeHash
        )
        let attachmentDescriptors = attachments.map { attachment in
            MailAttachmentDescriptor(
                id: attachment.id,
                messageID: messageID,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                byteCount: attachment.data.count,
                contentHash: attachment.contentHash
            )
        }
        try await cache.saveMessage(MailMessageDetail(
            summary: summary,
            headers: MailMessageHeaders(messageIDHeader: messageIDHeader, inReplyTo: draft.inReplyToHeader, references: draft.referencesHeaders, rawHeaderHash: receipt.envelopeHash),
            body: body,
            attachments: attachmentDescriptors
        ))
        NotificationCenter.default.post(
            name: .connorMailCacheDidChange,
            object: nil,
            userInfo: [
                MailCacheChangeNotificationUserInfoKey.accountID: draft.accountID.rawValue,
                MailCacheChangeNotificationUserInfoKey.messageID: messageID.rawValue,
                MailCacheChangeNotificationUserInfoKey.reason: MailCacheChangeReason.sentMessageSaved.rawValue
            ]
        )
        return sentMailbox
    }

    private func appendRemoteSentMessageIfPossible(account: MailAccount, password: String, draft: MailDraft, receipt: MailSendReceipt, rawMessage: String, sentMailbox: MailMailbox, runID: String?, sessionID: String?) async {
        guard account.incoming?.protocolKind == .imap else { return }
        do {
            _ = try await sentMessageRemoteAppender.appendSentMessage(
                account: account,
                password: password,
                rawMessage: rawMessage,
                mailboxPath: sentMailbox.path,
                sentAt: receipt.sentAt
            )
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: account.id, draftID: draft.id, kind: .stateMutated, riskClass: .mutation, redactedSummary: "Saved sent message to remote mailbox \(sentMailbox.path)", payloadHash: receipt.envelopeHash))
        } catch {
            try? await draftStore.recordSendAttempt(MailSendAttempt(draftID: draft.id, status: .failed, providerMessageID: receipt.providerMessageID, envelopeHash: receipt.envelopeHash, errorSummary: "Remote Sent APPEND failed: \(error)"))
            try? await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: account.id, draftID: draft.id, kind: .stateMutated, riskClass: .mutation, redactedSummary: "Mail sent, but saving to remote Sent mailbox failed: \(error)", payloadHash: receipt.envelopeHash))
        }
    }

    private func captureOutboundMemoryEvidence(draft: MailDraft, identity: MailIdentity, receipt: MailSendReceipt, runID: String?, sessionID: String?) throws {
        guard let memoryOSFacade else { return }
        let content = """
        Direction: outbound
        Subject: \(draft.subject)
        From: \(identity.address.name.map { "\($0) <\(identity.address.email)>" } ?? identity.address.email)
        To: \(draft.to.map(\.email).joined(separator: ", "))
        Cc: \(draft.cc.map(\.email).joined(separator: ", "))
        Bcc Count: \(draft.bcc.count)
        Body Preview: \(String(draft.body.prefix(500)))
        """
        _ = try memoryOSFacade.ingestSourceEvent(
            sourceID: "mail:sent:\(receipt.providerMessageID)",
            title: draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No subject)" : draft.subject,
            content: content,
            occurredAt: receipt.sentAt,
            sourceKind: "mail",
            accountID: draft.accountID.rawValue,
            sessionID: sessionID,
            metadata: [
                "direction": "outbound",
                "mail_draft_id": draft.id.rawValue,
                "provider_message_id": receipt.providerMessageID,
                "envelope_hash": receipt.envelopeHash,
                "run_id": runID ?? "",
                "identity_id": draft.identityID.rawValue,
                "recipient_count": String(draft.to.count + draft.cc.count + draft.bcc.count),
                "attachment_count": String(draft.attachmentIDs.count)
            ]
        )
    }

    public func evidenceCandidate(for messageID: MailMessageID) async throws -> MailEvidenceCandidate {
        let detail = try await getMessage(id: messageID, includeBody: false)
        let candidate = MailEvidenceCandidate(accountID: detail.summary.accountID, mailboxID: detail.summary.mailboxID, messageID: messageID, evidenceKind: "mail-message", redactedSummary: detail.summary.subject, sourceHash: detail.headers.rawHeaderHash)
        try await auditLog.record(MailAuditRecord(accountID: detail.summary.accountID, messageID: messageID, kind: .evidenceCandidateCreated, riskClass: .read, redactedSummary: candidate.redactedSummary, payloadHash: candidate.sourceHash))
        return candidate
    }
}

public struct NativeMailReadiness: Codable, Sendable, Equatable {
    public var accountCount: Int
    public var healthyAccountCount: Int
    public var credentialBoundaryReady: Bool
    public var syncCursorReady: Bool
    public var toolAuditReady: Bool
    public var sendApprovalReady: Bool
    public var smtpSendAdapterReady: Bool
    public var persistentDraftStoreReady: Bool
    public var contactApprovalReady: Bool
    public var attachmentImportReady: Bool
    public var evidencePolicyReady: Bool

    public var isReady: Bool {
        accountCount > 0 && healthyAccountCount > 0 && credentialBoundaryReady && syncCursorReady && toolAuditReady && sendApprovalReady && smtpSendAdapterReady && persistentDraftStoreReady && contactApprovalReady && attachmentImportReady && evidencePolicyReady
    }

    public init(accountCount: Int, healthyAccountCount: Int, credentialBoundaryReady: Bool, syncCursorReady: Bool, toolAuditReady: Bool, sendApprovalReady: Bool, smtpSendAdapterReady: Bool = true, persistentDraftStoreReady: Bool = true, contactApprovalReady: Bool, attachmentImportReady: Bool, evidencePolicyReady: Bool) {
        self.accountCount = accountCount
        self.healthyAccountCount = healthyAccountCount
        self.credentialBoundaryReady = credentialBoundaryReady
        self.syncCursorReady = syncCursorReady
        self.toolAuditReady = toolAuditReady
        self.sendApprovalReady = sendApprovalReady
        self.smtpSendAdapterReady = smtpSendAdapterReady
        self.persistentDraftStoreReady = persistentDraftStoreReady
        self.contactApprovalReady = contactApprovalReady
        self.attachmentImportReady = attachmentImportReady
        self.evidencePolicyReady = evidencePolicyReady
    }
}
