import Foundation
import ConnorGraphCore

public struct MailInitialSyncResult: Sendable, Equatable {
    public var account: MailAccount
    public var mailboxes: [MailMailbox]
    public var messages: [MailMessageDetail]

    public init(account: MailAccount, mailboxes: [MailMailbox], messages: [MailMessageDetail]) {
        self.account = account
        self.mailboxes = mailboxes
        self.messages = messages
    }
}

public struct MailIMAPInitialSyncService: Sendable {
    public var credentialStore: AppMailCredentialStore
    public var messageLimit: Int

    public init(credentialStore: AppMailCredentialStore = AppMailCredentialStore(), messageLimit: Int = 0) {
        self.credentialStore = credentialStore
        self.messageLimit = messageLimit
    }

    public func sync(account originalAccount: MailAccount, onBatch: (@Sendable ([MailMessageDetail]) -> Void)? = nil) async throws -> MailInitialSyncResult {
        if originalAccount.provider == .gmail || originalAccount.provider == .microsoft365 {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "此邮件账户类型已不再支持", reasons: ["请删除此旧账户后使用授权码、App Password 或通用 IMAP/SMTP 凭据重新添加。"]),
                mailboxes: [],
                messages: []
            )
        }
        guard let endpoint = originalAccount.incoming, endpoint.protocolKind == .imap else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "缺少 IMAP 收件服务器配置", reasons: ["Incoming endpoint is not IMAP"]),
                mailboxes: [],
                messages: []
            )
        }
        guard endpoint.security == .tls else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "首次同步仅允许 TLS IMAP", reasons: ["Direct TLS on port 993 is required for first sync"]),
                mailboxes: [],
                messages: []
            )
        }
        guard let binding = originalAccount.credentialBinding,
              let rawCredential = try credentialStore.readCredential(binding: binding),
              !rawCredential.isEmpty else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .unauthenticated, summary: "缺少邮件账户凭据", reasons: ["Missing Keychain credential"]),
                mailboxes: [],
                messages: []
            )
        }
        guard let email = originalAccount.identities.first?.address.email, !email.isEmpty else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "缺少邮箱地址", reasons: ["Missing mail identity address"]),
                mailboxes: [],
                messages: []
            )
        }

        do {
            if binding.authMode == .oauth2 {
                return MailInitialSyncResult(
                    account: updatedAccount(originalAccount, status: .blocked, summary: "OAuth 邮件登录已不再支持", reasons: ["请删除此旧账户后使用授权码、App Password 或通用 IMAP/SMTP 凭据重新添加。"]),
                    mailboxes: [],
                    messages: []
                )
            }
            let client = BlockingIMAPClient(host: endpoint.host, port: endpoint.port)
            let loginUsernames = Self.candidateUsernames(email: email, provider: originalAccount.provider)
            let accountID = originalAccount.id
            let inboxID = MailMailboxID(rawValue: "\(accountID.rawValue)-inbox")
            let onBatchWithDetail: (@Sendable ([BlockingIMAPClient.FetchedMessage]) -> Void)? = onBatch.map { callback in
                return { @Sendable (batch: [BlockingIMAPClient.FetchedMessage]) in
                    let details = batch.map { $0.detail(accountID: accountID, mailboxID: inboxID, fallbackRecipient: MailAddress(email: email)) }
                    callback(details)
                }
            }
            let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BlockingIMAPClient.Snapshot, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let result = try client.withPasswordSession(usernames: loginUsernames, password: rawCredential, messageLimit: self.messageLimit, onBatch: onBatchWithDetail)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let now = Date()
            let mailbox = MailMailbox(
                id: inboxID,
                accountID: accountID,
                name: "收件箱",
                path: "INBOX",
                role: .inbox,
                status: MailMailboxStatus(
                    messageCount: snapshot.exists,
                    unreadCount: snapshot.unreadCount,
                    syncCursor: snapshot.highestUID.map { MailSyncCursor(value: $0, updatedAt: now, uidValidity: snapshot.uidValidity) },
                    lastSyncedAt: now
                )
            )
            let messages = snapshot.messages.map { fetched in
                fetched.detail(accountID: accountID, mailboxID: inboxID, fallbackRecipient: MailAddress(email: email))
            }
            var account = originalAccount
            account.health = MailAccountHealth(
                status: .ready,
                checkedAt: now,
                summary: "首次同步完成 · INBOX \(snapshot.exists) 封 · 已拉取最近 \(messages.count) 封",
                blockingReasons: []
            )
            account.updatedAt = now
            return MailInitialSyncResult(account: account, mailboxes: [mailbox], messages: messages)
        } catch let error as BlockingIMAPClient.IMAPError {
            let health: MailAccountHealth
            switch error {
            case .authenticationFailed(let message):
                health = MailAccountHealth(status: .unauthenticated, summary: "IMAP 登录失败", blockingReasons: [message])
            case .connectionFailed(let message), .protocolError(let message):
                health = MailAccountHealth(status: .degraded, summary: "IMAP 首次同步失败", blockingReasons: [message])
            }
            var account = originalAccount
            account.health = health
            account.updatedAt = Date()
            return MailInitialSyncResult(account: account, mailboxes: [], messages: [])
        }
    }

    public func syncIncremental(account originalAccount: MailAccount, storedUIDs: Set<String>, storedUIDValidity: String? = nil, onBatch: (@Sendable ([MailMessageDetail]) -> Void)? = nil) async throws -> MailInitialSyncResult {
        guard let endpoint = originalAccount.incoming, endpoint.protocolKind == .imap else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "缺少 IMAP 收件服务器配置", reasons: ["Incoming endpoint is not IMAP"]),
                mailboxes: [],
                messages: []
            )
        }
        guard endpoint.security == .tls else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "增量同步仅允许 TLS IMAP", reasons: ["Direct TLS on port 993 is required"]),
                mailboxes: [],
                messages: []
            )
        }
        guard let binding = originalAccount.credentialBinding,
              let rawCredential = try credentialStore.readCredential(binding: binding),
              !rawCredential.isEmpty else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .unauthenticated, summary: "缺少邮件账户凭据", reasons: ["Missing Keychain credential"]),
                mailboxes: [],
                messages: []
            )
        }
        guard let email = originalAccount.identities.first?.address.email, !email.isEmpty else {
            return MailInitialSyncResult(
                account: updatedAccount(originalAccount, status: .blocked, summary: "缺少邮箱地址", reasons: ["Missing mail identity address"]),
                mailboxes: [],
                messages: []
            )
        }

        do {
            if binding.authMode == .oauth2 {
                return MailInitialSyncResult(
                    account: updatedAccount(originalAccount, status: .blocked, summary: "OAuth 邮件登录已不再支持", reasons: ["请删除此旧账户后使用授权码、App Password 或通用 IMAP/SMTP 凭据重新添加。"]),
                    mailboxes: [],
                    messages: []
                )
            }
            let client = BlockingIMAPClient(host: endpoint.host, port: endpoint.port)
            let loginUsernames = Self.candidateUsernames(email: email, provider: originalAccount.provider)
            let accountID = originalAccount.id
            let inboxID = MailMailboxID(rawValue: "\(accountID.rawValue)-inbox")
            let onBatchWithDetail: (@Sendable ([BlockingIMAPClient.FetchedMessage]) -> Void)? = onBatch.map { callback in
                return { @Sendable (batch: [BlockingIMAPClient.FetchedMessage]) in
                    let details = batch.map { $0.detail(accountID: accountID, mailboxID: inboxID, fallbackRecipient: MailAddress(email: email)) }
                    callback(details)
                }
            }
            let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BlockingIMAPClient.Snapshot, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let result = try client.withPasswordSessionIncremental(usernames: loginUsernames, password: rawCredential, storedUIDs: storedUIDs, storedUIDValidity: storedUIDValidity, onBatch: onBatchWithDetail)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let now = Date()
            let mailbox = MailMailbox(
                id: inboxID,
                accountID: accountID,
                name: "收件箱",
                path: "INBOX",
                role: .inbox,
                status: MailMailboxStatus(
                    messageCount: snapshot.exists,
                    unreadCount: snapshot.unreadCount,
                    syncCursor: snapshot.highestUID.map { MailSyncCursor(value: $0, updatedAt: now, uidValidity: snapshot.uidValidity) },
                    lastSyncedAt: now
                )
            )
            let messages = snapshot.messages.map { fetched in
                fetched.detail(accountID: accountID, mailboxID: inboxID, fallbackRecipient: MailAddress(email: email))
            }
            var account = originalAccount
            account.health = MailAccountHealth(
                status: .ready,
                checkedAt: now,
                summary: "增量同步完成 · INBOX \(snapshot.exists) 封 · 新拉取 \(messages.count) 封",
                blockingReasons: []
            )
            account.updatedAt = now
            return MailInitialSyncResult(account: account, mailboxes: [mailbox], messages: messages)
        } catch let error as BlockingIMAPClient.IMAPError {
            let health: MailAccountHealth
            switch error {
            case .authenticationFailed(let message):
                health = MailAccountHealth(status: .unauthenticated, summary: "IMAP 登录失败", blockingReasons: [message])
            case .connectionFailed(let message), .protocolError(let message):
                health = MailAccountHealth(status: .degraded, summary: "IMAP 增量同步失败", blockingReasons: [message])
            }
            var account = originalAccount
            account.health = health
            account.updatedAt = Date()
            return MailInitialSyncResult(account: account, mailboxes: [], messages: [])
        }
    }

    /// Fetch a single message's body from IMAP on demand (lazy loading).
    /// Used by AppViewModel when user opens a message that has no cached body.
    public func fetchMessageBody(account: MailAccount, uid: String, messageID: MailMessageID, mailboxID: MailMailboxID, snippet: String) async throws -> MailMessageDetail? {
        guard let endpoint = account.incoming, endpoint.protocolKind == .imap else { return nil }
        guard endpoint.security == .tls else { return nil }
        guard let binding = account.credentialBinding,
              let password = try credentialStore.readCredential(binding: binding),
              !password.isEmpty else { return nil }
        guard let email = account.identities.first?.address.email, !email.isEmpty else { return nil }

        let uidInt = Int(uid) ?? 0
        guard uidInt > 0 else { return nil }

        let client = BlockingIMAPClient(host: endpoint.host, port: endpoint.port)
        let loginUsernames = Self.candidateUsernames(email: email, provider: account.provider)
        let accountID = account.id

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let detail = try client.fetchSingleMessageBody(
                        usernames: loginUsernames, password: password,
                        uid: uid, accountID: accountID, mailboxID: mailboxID,
                        fallbackRecipient: MailAddress(email: email), snippet: snippet
                    )
                    continuation.resume(returning: detail)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Search emails by query string
    public func search(account: MailAccount, query: String) async throws -> [String] {
        guard let endpoint = account.incoming, endpoint.protocolKind == .imap else {
            throw BlockingIMAPClient.IMAPError.protocolError("缺少 IMAP 收件服务器配置")
        }
        guard endpoint.security == .tls else {
            throw BlockingIMAPClient.IMAPError.protocolError("搜索仅允许 TLS IMAP")
        }
        guard let binding = account.credentialBinding,
              let rawCredential = try credentialStore.readCredential(binding: binding),
              !rawCredential.isEmpty else {
            throw BlockingIMAPClient.IMAPError.authenticationFailed("缺少邮件账户凭据")
        }
        guard let email = account.identities.first?.address.email, !email.isEmpty else {
            throw BlockingIMAPClient.IMAPError.protocolError("缺少邮箱地址")
        }
        let client = BlockingIMAPClient(host: endpoint.host, port: endpoint.port)
        let loginUsernames = Self.candidateUsernames(email: email, provider: account.provider)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try client.search(usernames: loginUsernames, password: rawCredential, query: query)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func candidateUsernames(email: String, provider: MailProviderKind) -> [String] {
        var usernames = [email]
        if provider == .genericIMAPSMTP || provider == .localFixture || provider == .jmap {
            return usernames
        }
        if let local = email.split(separator: "@").first.map(String.init), !local.isEmpty {
            usernames.append(local)
        }
        return Array(NSOrderedSet(array: usernames)) as? [String] ?? usernames
    }

    private func updatedAccount(_ account: MailAccount, status: MailAccountHealthStatus, summary: String, reasons: [String]) -> MailAccount {
        var copy = account
        copy.health = MailAccountHealth(status: status, summary: summary, blockingReasons: reasons)
        copy.updatedAt = Date()
        return copy
    }
}

struct BlockingIMAPClient {
    enum IMAPError: Error, Sendable, Equatable, CustomStringConvertible {
        case connectionFailed(String)
        case authenticationFailed(String)
        case protocolError(String)

        var description: String {
            switch self {
            case .connectionFailed(let message), .authenticationFailed(let message), .protocolError(let message): message
            }
        }
    }

    struct Snapshot: Sendable, Equatable {
        var exists: Int
        var unreadCount: Int
        var uidValidity: String?
        var highestUID: String?
        var messages: [FetchedMessage]
    }

    struct FetchedMessage: Sendable, Equatable {
        var uid: String
        var flags: String
        var header: String
        var rawHeaderData: Data?  // Raw RFC 822 headers from BODY.PEEK[HEADER.FIELDS]
        var snippet: String
        var rawBodyData: Data?
        var fallbackSequenceDate: Date

        func detail(accountID: MailAccountID, mailboxID: MailMailboxID, fallbackRecipient: MailAddress) -> MailMessageDetail {
            // Parse headers: prefer raw RFC 822 headers (ASCII-safe, proper RFC 2047 decoding)
            // over synthetic header from ENVELOPE (may have lossy non-ASCII bytes).
            let rawHeaders: ParsedHeaders
            if let rawHeaderData {
                // Some servers (e.g. QQ, 163) send raw UTF-8 in BODY[HEADER.FIELDS] instead of
                // RFC 2047 encoded form. Try ASCII first (RFC 2047 is ASCII-safe), then UTF-8
                // (for raw non-ASCII headers), then Latin-1 as broad fallback.
                if let headerString = String(data: rawHeaderData, encoding: .ascii) {
                    rawHeaders = ParsedHeaders(raw: headerString)
                } else if let headerString = String(data: rawHeaderData, encoding: .utf8) {
                    // Raw UTF-8 header: content is already decoded, skip RFC 2047 decode
                    rawHeaders = ParsedHeaders(raw: headerString, skipRFC2047: true)
                } else if let headerString = String(data: rawHeaderData, encoding: .isoLatin1) {
                    rawHeaders = ParsedHeaders(raw: headerString)
                } else {
                    rawHeaders = ParsedHeaders(raw: header)
                }
            } else {
                rawHeaders = ParsedHeaders(raw: header)
            }
            let envHeaders = ParsedHeaders(raw: header)
            let messageID = envHeaders.messageID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "imap-uid-\(uid)"
            // Subject/From: prefer raw RFC 822 headers (proper RFC 2047 decoding)
            let subject = rawHeaders.subject?.nilIfEmpty ?? envHeaders.subject?.nilIfEmpty ?? "（无主题）"
            let from = MailAddress.parse(rawHeaders.from) ?? MailAddress.parse(envHeaders.from) ?? MailAddress(email: "unknown@example.com")
            // To/Cc/Date: use ENVELOPE data (structured, already parsed)
            let to = MailAddress.parseList(envHeaders.to)
            let date = envHeaders.date ?? fallbackSequenceDate
            // Charset extraction: try rawHeaderData with the same multi-encoding fallback
            let charset: String? = {
                guard let rawHeaderData else { return ParsedHeaders.extractCharset(from: header) }
                if let s = String(data: rawHeaderData, encoding: .ascii) { return ParsedHeaders.extractCharset(from: s) }
                if let s = String(data: rawHeaderData, encoding: .utf8) { return ParsedHeaders.extractCharset(from: s) }
                if let s = String(data: rawHeaderData, encoding: .isoLatin1) { return ParsedHeaders.extractCharset(from: s) }
                return ParsedHeaders.extractCharset(from: header)
            }()
            let mimeParser = MailMIMEParser()
            // Detect multipart: check rawBodyData for boundary= (the synthetic header from ENVELOPE
            // never contains Content-Type, so header-based detection is unreliable).
            // Use tolerant decoding: only scan first 2KB where MIME headers live (always ASCII-compatible),
            // and fall back to lossy UTF-8 decoding if strict UTF-8 fails.
            let boundary = rawBodyData.flatMap { data -> String? in
                let prefix = data.prefix(2048)
                if let str = String(data: prefix, encoding: .utf8) {
                    return MailMIMEParser().extractBoundaryFromContentType(str)
                }
                // Lossy UTF-8: tolerate non-UTF-8 bytes in the data prefix
                let lossy = String(decoding: prefix, as: Unicode.UTF8.self)
                return MailMIMEParser().extractBoundaryFromContentType(lossy)
            }
            // Use new parseBodyWithHTML that returns both plain text and HTML content
            let bodyResult = mimeParser.parseBodyWithHTML(
                rawData: rawBodyData, fallbackString: snippet,
                charset: charset, transferEncoding: rawHeaders.transferEncoding ?? envHeaders.transferEncoding,
                contentType: header, boundary: boundary
            )
            let cleanSnippet = bodyResult.plainText.htmlStripped.normalizedWhitespace.prefixString(300)
            let summary = MailMessageSummary(
                id: MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-\(uid)"),
                accountID: accountID,
                mailboxID: mailboxID,
                threadID: MailThreadID(rawValue: messageID),
                subject: subject,
                from: from,
                to: to.isEmpty ? [fallbackRecipient] : to,
                cc: MailAddress.parseList(envHeaders.cc),
                date: date,
                snippet: cleanSnippet.isEmpty ? "（无正文摘要）" : cleanSnippet,
                flags: MailMessageFlags(isRead: flags.localizedCaseInsensitiveContains("\\Seen"), isFlagged: flags.localizedCaseInsensitiveContains("\\Flagged"), isAnswered: flags.localizedCaseInsensitiveContains("\\Answered"), isDeleted: flags.localizedCaseInsensitiveContains("\\Deleted")),
                hasAttachments: header.localizedCaseInsensitiveContains("multipart/mixed")
            )
            let body = MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: bodyResult.plainText, byteCount: bodyResult.plainText.utf8.count, wasTruncated: false),
                htmlText: bodyResult.htmlText.map { MailBodyPart(mimeType: "text/html", text: $0, byteCount: $0.utf8.count) },
                redactedPreview: String(bodyResult.plainText.prefix(500)),
                bodyHash: String(abs(bodyResult.plainText.hashValue))
            )
            return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: envHeaders.messageID, rawHeaderHash: String(abs(header.hashValue))), body: body)
        }

        static func decodeQuotedPrintable(_ data: Data) -> Data {
            var result = Data()
            let bytes = [UInt8](data)
            var i = 0
            while i < bytes.count {
                if bytes[i] == 0x3D { // '='
                    // Soft line break: =\r\n or =\n
                    if i + 1 < bytes.count && bytes[i + 1] == 0x0A { // =\n
                        i += 2; continue
                    }
                    if i + 2 < bytes.count && bytes[i + 1] == 0x0D && bytes[i + 2] == 0x0A { // =\r\n
                        i += 3; continue
                    }
                    // Encoded byte: =XX
                    if i + 2 < bytes.count,
                       let hex = String(bytes: [bytes[i + 1], bytes[i + 2]], encoding: .utf8),
                       let byte = UInt8(hex, radix: 16) {
                        result.append(byte)
                        i += 3; continue
                    }
                }
                result.append(bytes[i])
                i += 1
            }
            return result
        }

        static func decodeBody(rawData: Data?, fallbackString: String, charset: String?, transferEncoding: String? = nil) -> String {
            guard let rawData, !rawData.isEmpty else { return fallbackString }

            // Step 1: Decode Content-Transfer-Encoding
            let decodedData: Data
            let enc = transferEncoding?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if enc == "quoted-printable" || enc == "qp" {
                decodedData = decodeQuotedPrintable(rawData)
            } else if enc == "base64" {
                decodedData = Data(base64Encoded: rawData) ?? rawData
            } else {
                decodedData = rawData
            }

            // Step 2: Charset conversion
            let charsetLower = charset?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if charsetLower.isEmpty || charsetLower == "utf-8" || charsetLower == "utf8" {
                return String(data: decodedData, encoding: .utf8) ?? fallbackString
            }
            let cfEncoding: CFStringEncoding
            switch charsetLower {
            case "gb2312", "gbk", "gb18030": cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            case "big5": cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
            case "iso-2022-jp": cfEncoding = CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
            case "euc-jp": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)
            case "shift_jis", "shift-jis": cfEncoding = CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
            case "euc-kr": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
            case "iso-8859-1", "latin1": cfEncoding = CFStringEncoding(0x0201) // kCFStringEncodingISOLatin1
            case "windows-1252", "cp1252": cfEncoding = CFStringEncoding(0x0500) // kCFStringEncodingWindowsLatin1
            case "iso-8859-2", "latin2": cfEncoding = CFStringEncoding(0x0202) // kCFStringEncodingISOLatin2
            case "windows-1251", "cp1251": cfEncoding = CFStringEncoding(0x0501) // kCFStringEncodingWindowsCyrillic
            case "koi8-r": cfEncoding = CFStringEncoding(0x0A02) // kCFStringEncodingKOI8_R
            default:
                return String(data: decodedData, encoding: .utf8) ?? String(data: decodedData, encoding: .ascii) ?? fallbackString
            }
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String(data: decodedData, encoding: String.Encoding(rawValue: nsEncoding)) ?? fallbackString
        }

        static func extractPlainTextPart(from body: String, boundary: String) -> String {
            let delimiter = "--\(boundary)"
            let parts = body.components(separatedBy: delimiter)
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("--") else { continue }
                let isPlainText = trimmed.range(of: #"Content-Type:\s*text/plain"#, options: [.caseInsensitive, .regularExpression]) != nil
                guard isPlainText else { continue }

                // Extract part-level Content-Transfer-Encoding
                let partHeaderEnd: String.Index?
                if let r = trimmed.range(of: "\r\n\r\n") { partHeaderEnd = r.upperBound }
                else if let r = trimmed.range(of: "\n\n") { partHeaderEnd = r.upperBound }
                else { partHeaderEnd = nil }
                guard let partBodyStart = partHeaderEnd else { continue }
                let partHeaders = String(trimmed[..<partBodyStart])
                var partBody = String(trimmed[partBodyStart...])

                // Decode per-part transfer encoding
                if let encMatch = partHeaders.range(of: #"Content-Transfer-Encoding:\s*(\S+)"#, options: [.caseInsensitive, .regularExpression]) {
                    let encValue = String(partHeaders[encMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let encLower = encValue.lowercased()
                    if encLower.hasPrefix("quoted-printable") {
                        let decoded = decodeQuotedPrintable(Data(partBody.utf8))
                        partBody = String(data: decoded, encoding: .utf8) ?? partBody
                    } else if encLower == "base64" {
                        if let decoded = Data(base64Encoded: partBody.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            partBody = String(data: decoded, encoding: .utf8) ?? partBody
                        }
                    }
                }
                return partBody.mimeCleanedBody
            }
            // No text/plain found — try text/html fallback with QP decode
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("--") else { continue }
                let isHTML = trimmed.range(of: #"Content-Type:\s*text/html"#, options: [.caseInsensitive, .regularExpression]) != nil
                guard isHTML else { continue }
                let partHeaderEnd: String.Index?
                if let r = trimmed.range(of: "\r\n\r\n") { partHeaderEnd = r.upperBound }
                else if let r = trimmed.range(of: "\n\n") { partHeaderEnd = r.upperBound }
                else { partHeaderEnd = nil }
                guard let partBodyStart = partHeaderEnd else { continue }
                let partHeaders = String(trimmed[..<partBodyStart])
                var partBody = String(trimmed[partBodyStart...])
                if let encMatch = partHeaders.range(of: #"Content-Transfer-Encoding:\s*(\S+)"#, options: [.caseInsensitive, .regularExpression]) {
                    let encValue = String(partHeaders[encMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if encValue.hasPrefix("quoted-printable") {
                        partBody = String(data: decodeQuotedPrintable(Data(partBody.utf8)), encoding: .utf8) ?? partBody
                    } else if encValue == "base64" {
                        partBody = String(data: Data(base64Encoded: partBody.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Data(), encoding: .utf8) ?? partBody
                    }
                }
                return partBody.mimeCleanedBody
            }
            return body.mimeCleanedBody
        }
    }

    var host: String
    var port: Int

    func withPasswordSession(usernames: [String], password: String, messageLimit: Int, onBatch: (@Sendable ([FetchedMessage]) -> Void)? = nil) throws -> Snapshot {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let readStream, let writeStream else { throw IMAPError.connectionFailed("Cannot create socket streams for \(host):\(port)") }
        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        let sslSettings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        input.setProperty(sslSettings, forKey: sslSettingsKey)
        output.setProperty(sslSettings, forKey: sslSettingsKey)
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        _ = try readUntilLine(input: input, timeout: 20)
        try authenticateWithPassword(usernames: usernames, password: password, input: input, output: output)
        return try fetchInboxSnapshot(input: input, output: output, messageLimit: messageLimit, onBatch: onBatch)
    }

    func withPasswordSessionIncremental(usernames: [String], password: String, storedUIDs: Set<String>, storedUIDValidity: String? = nil, fetchBatchSize: Int = 50, onBatch: (@Sendable ([FetchedMessage]) -> Void)? = nil) throws -> Snapshot {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let readStream, let writeStream else { throw IMAPError.connectionFailed("Cannot create socket streams for \(host):\(port)") }
        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        let sslSettings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        input.setProperty(sslSettings, forKey: sslSettingsKey)
        output.setProperty(sslSettings, forKey: sslSettingsKey)
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        _ = try readUntilLine(input: input, timeout: 20)
        try authenticateWithPassword(usernames: usernames, password: password, input: input, output: output)
        return try fetchInboxIncremental(input: input, output: output, storedUIDs: storedUIDs, storedUIDValidity: storedUIDValidity, fetchBatchSize: fetchBatchSize, onBatch: onBatch)
    }

    func withOAuth2Session(usernames: [String], accessToken: String, messageLimit: Int) throws -> Snapshot {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let readStream, let writeStream else { throw IMAPError.connectionFailed("Cannot create socket streams for \(host):\(port)") }
        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        let sslSettings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        input.setProperty(sslSettings, forKey: sslSettingsKey)
        output.setProperty(sslSettings, forKey: sslSettingsKey)
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        _ = try readUntilLine(input: input, timeout: 20)
        try authenticateWithOAuth2(usernames: usernames, accessToken: accessToken, input: input, output: output)
        return try fetchInboxSnapshot(input: input, output: output, messageLimit: messageLimit)
    }

    private func authenticateWithPassword(usernames: [String], password: String, input: InputStream, output: OutputStream) throws {
        var authenticated = false
        var lastLoginError = "Authentication failed"
        for username in usernames {
            let tag = nextTag()
            try write("\(tag) LOGIN \"\(escape(username))\" \"\(escape(password))\"\r\n", output: output)
            let response = try readUntilTagged(tag: tag, input: input, timeout: 30)
            if response.contains("\(tag) OK") {
                authenticated = true
                break
            }
            lastLoginError = response.lastLine ?? response
        }
        guard authenticated else { throw IMAPError.authenticationFailed(lastLoginError) }
    }

    private func authenticateWithOAuth2(usernames: [String], accessToken: String, input: InputStream, output: OutputStream) throws {
        var authenticated = false
        var lastLoginError = "OAuth2 authentication failed"
        for username in usernames {
            let tag = nextTag()
            let xoauth2 = "user=\(username)\u{001}auth=Bearer \(accessToken)\u{001}\u{001}"
            let payload = Data(xoauth2.utf8).base64EncodedString()
            try write("\(tag) AUTHENTICATE XOAUTH2 \(payload)\r\n", output: output)
            let response = try readUntilTagged(tag: tag, input: input, timeout: 30)
            if response.contains("\(tag) OK") {
                authenticated = true
                break
            }
            lastLoginError = response.lastLine ?? response
        }
        guard authenticated else { throw IMAPError.authenticationFailed(lastLoginError) }
    }

    private func fetchInboxIncremental(input: InputStream, output: OutputStream, storedUIDs: Set<String>, storedUIDValidity: String? = nil, fetchBatchSize: Int, onBatch: (@Sendable ([FetchedMessage]) -> Void)? = nil) throws -> Snapshot {
        let statusTag = nextTag()
        try write("\(statusTag) STATUS \"INBOX\" (MESSAGES UNSEEN UIDVALIDITY UIDNEXT)\r\n", output: output)
        let statusResponse = try readUntilTagged(tag: statusTag, input: input, timeout: 30)
        let statusMessages = statusResponse.firstInt(matching: #"MESSAGES\s+(\d+)"#)
        let statusUnseen = statusResponse.firstInt(matching: #"UNSEEN\s+(\d+)"#)
        let statusUIDValidity = statusResponse.firstString(matching: #"UIDVALIDITY\s+(\d+)"#)

        let selectTag = nextTag()
        try write("\(selectTag) SELECT \"INBOX\"\r\n", output: output)
        let selectResponse = try readUntilTagged(tag: selectTag, input: input, timeout: 30)
        guard selectResponse.contains("\(selectTag) OK") else {
            throw IMAPError.protocolError(selectResponse.lastLine ?? "SELECT INBOX failed")
        }
        let exists = statusMessages ?? selectResponse.firstInt(matching: #"\*\s+(\d+)\s+EXISTS"#) ?? 0
        let uidValidity = statusUIDValidity ?? selectResponse.firstString(matching: #"UIDVALIDITY\s+(\d+)"#)

        // Check UIDVALIDITY - if it changed, mailbox was reset, need full resync
        if let storedValidity = storedUIDValidity, let currentValidity = uidValidity, storedValidity != currentValidity {
            throw IMAPError.protocolError("UIDVALIDITY changed (\(storedValidity) -> \(currentValidity)), full resync required")
        }

        guard exists > 0 else {
            try logout(input: input, output: output)
            return Snapshot(exists: 0, unreadCount: 0, uidValidity: uidValidity, highestUID: nil, messages: [])
        }

        // Phase 1: Fetch all UIDs and flags
        let uidTag = nextTag()
        try write("\(uidTag) UID FETCH 1:* (UID FLAGS)\r\n", output: output)
        let uidResponse = try readUntilTagged(tag: uidTag, input: input, timeout: 60)
        let allServerUIDs = parseUIDList(uidResponse)

        // Phase 2: Find new UIDs not in store
        let newUIDs = allServerUIDs.filter { !storedUIDs.contains($0) }.compactMap(Int.init).sorted()

        guard !newUIDs.isEmpty else {
            try logout(input: input, output: output)
            return Snapshot(exists: exists, unreadCount: statusUnseen ?? 0, uidValidity: uidValidity, highestUID: allServerUIDs.compactMap(Int.init).max().map(String.init), messages: [])
        }

        // Phase 3: Batch-fetch new messages
        var allMessages: [FetchedMessage] = []
        for batchStart in stride(from: 0, to: newUIDs.count, by: fetchBatchSize) {
            let batchEnd = min(batchStart + fetchBatchSize, newUIDs.count)
            let batch = Array(newUIDs[batchStart..<batchEnd])
            let uidRange = "\(batch.first!):\(batch.last!)"
            let fetchTag = nextTag()
            // Incremental sync: fetch only headers — no body text
            try write("\(fetchTag) UID FETCH \(uidRange) (UID FLAGS ENVELOPE BODY.PEEK[HEADER.FIELDS (Subject From Content-Type)])\r\n", output: output)
            let (fetchResponse, fetchRaw) = try readUntilTaggedRaw(tag: fetchTag, input: input, timeout: 120)
            let batchMessages = parseFetchedMessages(fetchResponse, rawData: fetchRaw)
            allMessages.append(contentsOf: batchMessages)
            if !batchMessages.isEmpty { onBatch?(batchMessages) }
        }

        try logout(input: input, output: output)
        return Snapshot(exists: exists, unreadCount: statusUnseen ?? allMessages.filter { !$0.flags.localizedCaseInsensitiveContains("\\Seen") }.count, uidValidity: uidValidity, highestUID: allServerUIDs.compactMap(Int.init).max().map(String.init), messages: allMessages.sorted { (Int($0.uid) ?? 0) > (Int($1.uid) ?? 0) })
    }

    private func parseUIDList(_ response: String) -> [String] {
        let chunks = response.components(separatedBy: "\r\n* ")
        return chunks.compactMap { chunk -> String? in
            guard chunk.contains(" FETCH ") else { return nil }
            return chunk.firstString(matching: #"UID\s+(\d+)"#)
        }
    }

    private func fetchInboxSnapshot(input: InputStream, output: OutputStream, messageLimit: Int, onBatch: (@Sendable ([FetchedMessage]) -> Void)? = nil) throws -> Snapshot {
        let statusTag = nextTag()
        try write("\(statusTag) STATUS \"INBOX\" (MESSAGES UNSEEN UIDVALIDITY UIDNEXT)\r\n", output: output)
        let statusResponse = try readUntilTagged(tag: statusTag, input: input, timeout: 30)
        let statusMessages = statusResponse.firstInt(matching: #"MESSAGES\s+(\d+)"#)
        let statusUnseen = statusResponse.firstInt(matching: #"UNSEEN\s+(\d+)"#)
        let statusUIDValidity = statusResponse.firstString(matching: #"UIDVALIDITY\s+(\d+)"#)

        let selectTag = nextTag()
        try write("\(selectTag) SELECT \"INBOX\"\r\n", output: output)
        let selectResponse = try readUntilTagged(tag: selectTag, input: input, timeout: 30)
        guard selectResponse.contains("\(selectTag) OK") else {
            throw IMAPError.protocolError(selectResponse.lastLine ?? "SELECT INBOX failed")
        }
        let exists = statusMessages ?? selectResponse.firstInt(matching: #"\*\s+(\d+)\s+EXISTS"#) ?? 0
        let uidValidity = statusUIDValidity ?? selectResponse.firstString(matching: #"UIDVALIDITY\s+(\d+)"#)
        guard exists > 0 else {
            try logout(input: input, output: output)
            return Snapshot(exists: 0, unreadCount: 0, uidValidity: uidValidity, highestUID: nil, messages: [])
        }

        // Phase 1: Fetch all UIDs to get correct UID list
        let uidTag = nextTag()
        try write("\(uidTag) UID FETCH 1:* (UID FLAGS)\r\n", output: output)
        let uidResponse = try readUntilTagged(tag: uidTag, input: input, timeout: 60)
        let allUIDs = parseUIDList(uidResponse).compactMap(Int.init).sorted()

        // Phase 2: Take UIDs (0 = all, >0 = latest N)
        let fetchUIDs = messageLimit > 0 ? Array(allUIDs.suffix(messageLimit)) : allUIDs
        guard !fetchUIDs.isEmpty else {
            try logout(input: input, output: output)
            return Snapshot(exists: exists, unreadCount: statusUnseen ?? 0, uidValidity: uidValidity, highestUID: allUIDs.last.map(String.init), messages: [])
        }

        var allMessages: [FetchedMessage] = []
        // Initial sync: fetch only headers, envelope and flags. NO body text.
        // Body is fetched on-demand when user opens a message (see Task 2).
        // Larger batch size (50 instead of 5) significantly reduces round trips.
        let batchSize = 50
        for batchStart in stride(from: 0, to: fetchUIDs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, fetchUIDs.count)
            let batch = Array(fetchUIDs[batchStart..<batchEnd])
            let uidRange = "\(batch.first!):\(batch.last!)"
            let fetchTag = nextTag()
            // Fetch only envelope and key headers — no body text
            try write("\(fetchTag) UID FETCH \(uidRange) (UID FLAGS ENVELOPE BODY.PEEK[HEADER.FIELDS (Subject From Content-Type)])\r\n", output: output)
            let (fetchResponse, fetchRaw) = try readUntilTaggedRaw(tag: fetchTag, input: input, timeout: 120)
            let batchMessages = parseFetchedMessages(fetchResponse, rawData: fetchRaw)
            allMessages.append(contentsOf: batchMessages)
            if !batchMessages.isEmpty { onBatch?(batchMessages) }
        }

        try logout(input: input, output: output)
        return Snapshot(exists: exists, unreadCount: statusUnseen ?? allMessages.filter { !$0.flags.localizedCaseInsensitiveContains("\\Seen") }.count, uidValidity: uidValidity, highestUID: allUIDs.last.map(String.init), messages: allMessages.sorted { (Int($0.uid) ?? 0) > (Int($1.uid) ?? 0) })
    }

    private func parseFetchedMessages(_ response: String, rawData: Data? = nil) -> [FetchedMessage] {
        // Use state machine on raw bytes to extract everything reliably
        if let rawData {
            return parseFetchedMessagesFromRaw(rawData)
        }
        // Fallback: string-based parsing (no raw data)
        let chunks = response.components(separatedBy: "\r\n* ").map { $0.hasPrefix("* ") ? $0 : "* " + $0 }
        return chunks.compactMap { chunk -> FetchedMessage? in
            guard chunk.contains(" FETCH "), let uid = chunk.firstString(matching: #"UID\s+(\d+)"#) else { return nil }
            let flags = chunk.firstString(matching: #"FLAGS\s+\(([^)]*)\)"#) ?? ""
            let header = extractHeader(from: chunk)
            let body = extractBody(from: chunk, after: header)
            return FetchedMessage(uid: uid, flags: flags, header: header, rawHeaderData: nil, snippet: body, rawBodyData: nil, fallbackSequenceDate: Date())
        }.sorted { (Int($0.uid) ?? 0) > (Int($1.uid) ?? 0) }
    }

    /// State machine parser: extracts UID, flags, ENVELOPE, and body from raw IMAP bytes.
    private func parseFetchedMessagesFromRaw(_ data: Data) -> [FetchedMessage] {
        let bytes = [UInt8](data)
        let envelopeMarker = Array("ENVELOPE ".utf8)
        let textMarker = Array("BODY[TEXT]".utf8)
        let fetchMarker = Array(" FETCH ".utf8)
        let uidMarker = Array("UID ".utf8)
        let flagsMarker = Array("FLAGS (".utf8)

        var results: [FetchedMessage] = []
        var i = 0

        while i < bytes.count {
            if bytes[i] == 0x2A { // '*'
                let fetchSearch = Array(bytes[i..<min(i + 300, bytes.count)])
                guard let fetchIdx = findPattern(fetchSearch, fetchMarker) else { i += 1; continue }

                // Extract UID
                let afterFetch = Array(bytes[(i + fetchIdx + fetchMarker.count)..<min(i + fetchIdx + fetchMarker.count + 200, bytes.count)])
                var uid = ""
                if let uidIdx = findPattern(afterFetch, uidMarker) {
                    let uidStart = uidIdx + uidMarker.count
                    for j in uidStart..<afterFetch.count {
                        let c = Character(UnicodeScalar(afterFetch[j]))
                        if c.isNumber { uid.append(c) } else { break }
                    }
                }
                guard !uid.isEmpty else { i += 1; continue }

                // Extract FLAGS
                var flags = ""
                if let flagsIdx = findPattern(afterFetch, flagsMarker) {
                    let flagsStart = flagsIdx + flagsMarker.count
                    var f = ""
                    for j in flagsStart..<afterFetch.count {
                        if afterFetch[j] == 0x29 { break }
                        f.append(Character(UnicodeScalar(afterFetch[j])))
                    }
                    flags = f
                }

                // Find ENVELOPE and extract subject, from, to, cc, date
                var subject = ""
                var fromAddress: MailAddress?
                var toAddresses: [MailAddress] = []
                var ccAddresses: [MailAddress] = []
                var envelopeDate: Date?
                var envelopeEndPos = i

                let envSearch = Array(bytes[i..<min(i + 2000, bytes.count)])
                if let envIdx = findPattern(envSearch, envelopeMarker) {
                    // Find the matching closing paren for ENVELOPE (...)
                    let envStart = i + envIdx + envelopeMarker.count
                    // ENVELOPE starts with '('
                    if envStart < bytes.count && bytes[envStart] == 0x28 {
                        // Extract ENVELOPE content by counting parens in raw bytes.
                        // Use tolerant UTF-8 decoding instead of byte-by-byte Character(UnicodeScalar(b))
                        // which garbles non-ASCII bytes (e.g. Chinese subjects).
                        var depth = 1
                        var j = envStart + 1
                        while j < bytes.count && depth > 0 {
                            if bytes[j] == 0x28 { depth += 1 }
                            else if bytes[j] == 0x29 { depth -= 1 }
                            if depth == 0 { break }
                            j += 1
                        }
                        let envEndPos = j < bytes.count ? j + 1 : bytes.count
                        envelopeEndPos = envEndPos
                        let envData = Data(bytes[envStart..<envEndPos])
                        // Use lossy UTF-8: replaces invalid byte sequences with U+FFFD
                        // instead of corrupting them via Latin-1 byte-by-byte conversion.
                        let envContent = String(decoding: envData, as: Unicode.UTF8.self)
                        // Parse ENVELOPE: ("date" "subject" (from) (sender) (reply-to) (to) (cc) (bcc) "in-reply-to" "message-id")
                        let parsed = parseEnvelope(envContent)
                        subject = parsed.subject
                        fromAddress = parsed.from
                        toAddresses = parsed.to
                        ccAddresses = parsed.cc
                        envelopeDate = parsed.date
                    }
                }

                // Find BODY[HEADER.FIELDS] literal (raw RFC 822 headers)
                var rawHeaderData: Data? = nil
                let headerFieldsMarker = Array("BODY[HEADER.FIELDS".utf8)
                let headerSearch = Array(bytes[envelopeEndPos..<min(envelopeEndPos + 1000, bytes.count)])
                if let hfIdx = findPattern(headerSearch, headerFieldsMarker) {
                    // Find the ']' after HEADER.FIELDS (...)
                    let afterHf = Array(bytes[(envelopeEndPos + hfIdx)..<min(envelopeEndPos + hfIdx + 500, bytes.count)])
                    if let closeBracketIdx = findPattern(afterHf, Array("]".utf8)) {
                        let afterBracket = Array(bytes[(envelopeEndPos + hfIdx + closeBracketIdx + 1)..<min(envelopeEndPos + hfIdx + closeBracketIdx + 200, bytes.count)])
                        // Look for {NNN}\r\n literal size
                        if afterBracket.count > 3 && afterBracket[0] == 0x7B {
                            var sizeStr = ""
                            var k = 1
                            while k < afterBracket.count && afterBracket[k] != 0x7D {
                                sizeStr.append(Character(UnicodeScalar(afterBracket[k])))
                                k += 1
                            }
                            if k < afterBracket.count && afterBracket[k] == 0x7D, let headerSize = Int(sizeStr) {
                                let headerStart = envelopeEndPos + hfIdx + closeBracketIdx + 1 + k + 1 + 2 // skip }\r\n
                                let headerEnd = headerStart + headerSize
                                if headerEnd <= bytes.count {
                                    rawHeaderData = Data(bytes[headerStart..<headerEnd])
                                }
                            }
                        }
                    }
                }

                // Find BODY[TEXT] literal starting from after ENVELOPE
                var bodyData: Data? = nil
                // Calculate fetch end position: when BODY[TEXT] is present, use its end.
                // When absent (initial/incremental sync without bodies), use HEADER.FIELDS end.
                // This is critical — without it, the parser state machine loses sync and
                // produces garbage for all subsequent messages.
                var fetchEndPos = envelopeEndPos
                let bodySearch = Array(bytes[envelopeEndPos..<min(envelopeEndPos + 1500, bytes.count)])
                if let bodyIdx = findPattern(bodySearch, textMarker) {
                    let afterBody = Array(bytes[(envelopeEndPos + bodyIdx + textMarker.count)..<min(envelopeEndPos + bodyIdx + textMarker.count + 100, bytes.count)])
                    if let closeBraceIdx = findPattern(afterBody, Array("}\r\n".utf8)) {
                        var sizeStr = ""
                        for k in 0..<closeBraceIdx {
                            let c = Character(UnicodeScalar(afterBody[k]))
                            if c == "{" { continue }
                            if c.isNumber { sizeStr.append(c) }
                        }
                        if let bodySize = Int(sizeStr) {
                            let bodyStart = envelopeEndPos + bodyIdx + textMarker.count + closeBraceIdx + 3
                            let bodyEnd = bodyStart + bodySize
                            if bodyEnd <= bytes.count {
                                bodyData = Data(bytes[bodyStart..<bodyEnd])
                                fetchEndPos = bodyEnd + 2
                            }
                        }
                    }
                } else if let rawHeaderData {
                    // No BODY[TEXT] — advance past HEADER.FIELDS literal end
                    // The HEADER.FIELDS literal position was calculated above.
                    // Find the end of HEADER.FIELDS literal to set fetchEndPos.
                    let headerSearch2 = Array(bytes[envelopeEndPos..<min(envelopeEndPos + 1000, bytes.count)])
                    if let hfIdx2 = findPattern(headerSearch2, headerFieldsMarker) {
                        let afterHf2 = Array(bytes[(envelopeEndPos + hfIdx2)..<min(envelopeEndPos + hfIdx2 + 500, bytes.count)])
                        if let closeBracketIdx2 = findPattern(afterHf2, Array("]".utf8)) {
                            let afterBracket2 = Array(bytes[(envelopeEndPos + hfIdx2 + closeBracketIdx2 + 1)..<min(envelopeEndPos + hfIdx2 + closeBracketIdx2 + 200, bytes.count)])
                            if afterBracket2.count > 3 && afterBracket2[0] == 0x7B {
                                var sizeStr2 = ""
                                var k2 = 1
                                while k2 < afterBracket2.count && afterBracket2[k2] != 0x7D {
                                    sizeStr2.append(Character(UnicodeScalar(afterBracket2[k2])))
                                    k2 += 1
                                }
                                if k2 < afterBracket2.count && afterBracket2[k2] == 0x7D, let headerSize2 = Int(sizeStr2) {
                                    let headerStart2 = envelopeEndPos + hfIdx2 + closeBracketIdx2 + 1 + k2 + 1 + 2
                                    let headerEnd2 = headerStart2 + headerSize2
                                    if headerEnd2 <= bytes.count {
                                        fetchEndPos = headerEnd2 + 2 // skip closing \r\n
                                    }
                                }
                            }
                        }
                    }
                }

                // Build header string from ENVELOPE data (for compatibility)
                var headerParts: [String] = []
                if !subject.isEmpty { headerParts.append("Subject: \(subject)") }
                if let from = fromAddress {
                    let fromStr = from.name.map { "\($0) <\(from.email)>" } ?? from.email
                    headerParts.append("From: \(fromStr)")
                }
                if !toAddresses.isEmpty {
                    let toStr = toAddresses.map { a in a.name.map { "\($0) <\(a.email)>" } ?? a.email }.joined(separator: ", ")
                    headerParts.append("To: \(toStr)")
                }
                if !ccAddresses.isEmpty {
                    let ccStr = ccAddresses.map { a in a.name.map { "\($0) <\(a.email)>" } ?? a.email }.joined(separator: ", ")
                    headerParts.append("Cc: \(ccStr)")
                }
                let headerString = headerParts.joined(separator: "\r\n")

                // Use lossy UTF-8 for snippet so non-UTF-8 body data produces"."some readable content"at."instead"of"empty"string.
                let snippet: String = {
                    guard let bodyData else { return "" }
                    if let s = String(data: bodyData, encoding: .utf8) { return s }
                    return String(decoding: bodyData, as: Unicode.UTF8.self)
                }()
                results.append(FetchedMessage(
                    uid: uid, flags: flags, header: headerString, rawHeaderData: rawHeaderData,
                    snippet: snippet,
                    rawBodyData: bodyData, fallbackSequenceDate: envelopeDate ?? Date()
                ))

                i = fetchEndPos
                continue
            }
            i += 1
        }

        return results.sorted { (Int($0.uid) ?? 0) > (Int($1.uid) ?? 0) }
    }

    /// Parse IMAP ENVELOPE string: ("date" "subject" (from) (sender) (reply-to) (to) (cc) (bcc) "in-reply-to" "message-id")
    private struct ParsedEnvelope {
        var subject: String = ""
        var from: MailAddress?
        var to: [MailAddress] = []
        var cc: [MailAddress] = []
        var date: Date?
    }

    private func parseEnvelope(_ env: String) -> ParsedEnvelope {
        var result = ParsedEnvelope()
        // Split envelope into fields: date, subject, from, sender, reply-to, to, cc, bcc, in-reply-to, message-id
        let fields = splitEnvelopeFields(env)
        guard fields.count >= 8 else { return result }
        // fields[0] = date (quoted), fields[1] = subject (quoted)
        // fields[2] = from (address list), fields[3] = sender, fields[4] = reply-to
        // fields[5] = to, fields[6] = cc, fields[7] = bcc
        result.date = parseIMAPDate(fields[0])
        result.subject = unquoteIMAP(fields[1])
        result.from = parseIMAPAddressList(fields[2]).first
        result.to = parseIMAPAddressList(fields[5])
        result.cc = parseIMAPAddressList(fields[6])
        return result
    }

    /// Split ENVELOPE content into 10 fields, respecting nested parentheses
    private func splitEnvelopeFields(_ env: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        var escapeNext = false
        for ch in env {
            if escapeNext { current.append(ch); escapeNext = false; continue }
            if ch == "\\" && inQuote { current.append(ch); escapeNext = true; continue }
            if ch == "\"" { inQuote = !inQuote; current.append(ch); continue }
            if !inQuote {
                if ch == "(" { depth += 1 }
                else if ch == ")" { depth -= 1 }
            }
            // Split on space at depth 0, outside quotes
            if ch == " " && depth == 0 && !inQuote {
                if !current.isEmpty {
                    fields.append(current)
                    current = ""
                }
                continue
            }
            if depth > 0 || (depth == 0 && ch != "(") {
                current.append(ch)
            }
        }
        if !current.isEmpty { fields.append(current) }
        return fields
    }

    /// Remove surrounding quotes from IMAP string
    private func unquoteIMAP(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Parse IMAP address list: (("name" "route" "mailbox" "host") ...)
    private func parseIMAPAddressList(_ s: String) -> [MailAddress] {
        var addresses: [MailAddress] = []
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Each address is ("name" NIL "mailbox" "host")
        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            if trimmed[i] == "(" {
                // Find matching close paren
                var depth = 0
                var j = i
                while j < trimmed.endIndex {
                    if trimmed[j] == "(" { depth += 1 }
                    else if trimmed[j] == ")" { depth -= 1; if depth == 0 { break } }
                    j = trimmed.index(after: j)
                }
                if j < trimmed.endIndex {
                    let addrStr = String(trimmed[trimmed.index(after: i)..<j])
                    let parts = splitIMAPQuoted(addrStr)
                    if parts.count >= 4 {
                        let name = unquoteIMAP(parts[0])
                        let mailbox = unquoteIMAP(parts[2])
                        let host = unquoteIMAP(parts[3])
                        if !mailbox.isEmpty && !host.isEmpty {
                            let email = "\(mailbox)@\(host)"
                            addresses.append(MailAddress(name: name.isEmpty ? nil : name, email: email))
                        }
                    }
                    i = trimmed.index(after: j)
                    continue
                }
            }
            i = trimmed.index(after: i)
        }
        return addresses
    }

    /// Split IMAP quoted fields, respecting quotes
    private func splitIMAPQuoted(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote = false
        for ch in s {
            if ch == "\"" { inQuote = !inQuote; current.append(ch); continue }
            if ch == " " && !inQuote {
                if !current.isEmpty { parts.append(current); current = "" }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Parse IMAP date string: "dd-Mon-yyyy HH:mm:ss +HHMM"
    private func parseIMAPDate(_ s: String) -> Date? {
        let cleaned = unquoteIMAP(s)
        guard !cleaned.isEmpty && cleaned != "NIL" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["dd-MMM-yyyy HH:mm:ss Z", "dd-MMM-yyyy HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    /// Parse raw IMAP response bytes sequentially to extract BODY[TEXT] byte ranges per UID.
    /// Uses a simple state machine that respects literal sizes, so it never confuses
    /// "BODY[TEXT]" appearing inside email content with the actual IMAP literal marker.
    private func extractBodyRanges(from data: Data) -> [String: Range<Data.Index>] {
        var result: [String: Range<Data.Index>] = [:]
        let bytes = [UInt8](data)
        let marker = Array("BODY[TEXT]".utf8)
        let uidMarker = Array("UID ".utf8)
        let fetchMarker = Array(" FETCH ".utf8)
        let crlf = Array("\r\n".utf8)

        var i = 0
        var currentUID: String?

        while i < bytes.count {
            // Look for "* NNN FETCH " to identify a new FETCH response
            if bytes[i] == 0x2A { // '*'
                // Try to find "UID " after FETCH
                let slice = Array(bytes[i..<min(i + 200, bytes.count)])
                if let fetchIdx = findPattern(slice, fetchMarker) {
                    let afterFetch = Array(bytes[(i + fetchIdx + fetchMarker.count)..<min(i + fetchIdx + fetchMarker.count + 100, bytes.count)])
                    if let uidIdx = findPattern(afterFetch, uidMarker) {
                        let uidStart = uidIdx + uidMarker.count
                        var uid = ""
                        for j in uidStart..<afterFetch.count {
                            let c = Character(UnicodeScalar(afterFetch[j]))
                            if c.isNumber { uid.append(c) } else { break }
                        }
                        if !uid.isEmpty { currentUID = uid }
                    }
                }
            }

            // Look for "BODY[TEXT]{NNN}\r\n" marker
            if i + marker.count <= bytes.count {
                let slice = Array(bytes[i..<(i + marker.count)])
                if slice == marker {
                    let afterMarker = i + marker.count
                    // Find {NNN}
                    if afterMarker < bytes.count && bytes[afterMarker] == 0x7B { // '{'
                        var sizeStr = ""
                        var j = afterMarker + 1
                        while j < bytes.count && bytes[j] != 0x7D { // not '}'
                            sizeStr.append(Character(UnicodeScalar(bytes[j])))
                            j += 1
                        }
                        if j < bytes.count && bytes[j] == 0x7D, let literalSize = Int(sizeStr) {
                            let bodyStart = j + 1 + 2 // skip '}\r\n'
                            let bodyEnd = bodyStart + literalSize
                            if bodyEnd <= bytes.count, let uid = currentUID {
                                result[uid] = bodyStart..<bodyEnd
                            }
                            i = min(bodyEnd, bytes.count)
                            continue
                        }
                    }
                }
            }
            i += 1
        }
        return result
    }

    /// Find pattern in bytes using simple search
    private func findPattern(_ bytes: [UInt8], _ pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for i in 0...(bytes.count - pattern.count) {
            var match = true
            for j in 0..<pattern.count {
                if bytes[i + j] != pattern[j] { match = false; break }
            }
            if match { return i }
        }
        return nil
    }

    private func extractHeader(from chunk: String) -> String {
        guard let range = chunk.range(of: "BODY[HEADER.FIELDS", options: [.caseInsensitive]) else { return chunk }
        let tail = chunk[range.upperBound...]
        guard let literalStart = tail.range(of: "}\r\n") else { return String(tail) }
        let afterLiteral = tail[literalStart.upperBound...]
        if let bodyRange = afterLiteral.range(of: "BODY[TEXT]", options: [.caseInsensitive]) {
            return String(afterLiteral[..<bodyRange.lowerBound])
        }
        return String(afterLiteral)
    }

    private func extractBody(from chunk: String, after header: String) -> String {
        guard let range = chunk.range(of: "BODY[TEXT]", options: [.caseInsensitive]) else { return "" }
        let tail = chunk[range.upperBound...]
        guard let literalStart = tail.range(of: "}\r\n") else { return String(tail) }
        var body = String(tail[literalStart.upperBound...])
        if let close = body.range(of: "\r\n)") {
            body = String(body[..<close.lowerBound])
        }
        return body
    }

    private func extractBodyAsData(from chunk: String, rawData: Data?) -> Data? {
        guard let rawData else { return nil }
        // Find BODY[TEXT] in raw bytes
        let marker = Array("BODY[TEXT]".utf8)
        guard let markerRange = rawData.range(of: Data(marker)) else { return nil }
        let afterMarker = rawData[markerRange.upperBound...]
        // Find the opening brace for literal size: {NNN}

        guard let openBrace = afterMarker.firstIndex(of: 0x7B) else { return nil } // 0x7B = '{'
        // Find closing brace
        guard let closeBrace = afterMarker[openBrace...].firstIndex(of: 0x7D) else { return nil } // 0x7D = '}'
        let sizeBytes = afterMarker[afterMarker.index(openBrace, offsetBy: 1)..<closeBrace]
        guard let literalSize = Int(String(data: sizeBytes, encoding: .utf8) ?? "") else { return nil }
        let bodyStart = afterMarker.index(closeBrace, offsetBy: 3)
        let bodyStartOffset = bodyStart - rawData.startIndex
        guard bodyStartOffset >= 0, bodyStartOffset + literalSize <= rawData.count else { return nil }
        return rawData.subdata(in: bodyStartOffset..<(bodyStartOffset + literalSize))
    }

    /// Fetch a single message's full body (BODY[TEXT]) from IMAP.
    /// Used for lazy loading when user opens a message.
    func fetchSingleMessageBody(usernames: [String], password: String, uid: String, accountID: MailAccountID, mailboxID: MailMailboxID, fallbackRecipient: MailAddress, snippet: String) throws -> MailMessageDetail? {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let readStream, let writeStream else { throw IMAPError.connectionFailed("Cannot create socket streams for \(host):\(port)") }
        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        let sslSettings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        input.setProperty(sslSettings, forKey: sslSettingsKey)
        output.setProperty(sslSettings, forKey: sslSettingsKey)
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        _ = try readUntilLine(input: input, timeout: 20)
        try authenticateWithPassword(usernames: usernames, password: password, input: input, output: output)
        let selectTag = nextTag()
        try write("\(selectTag) SELECT \"INBOX\"\r\n", output: output)
        let selectResponse = try readUntilTagged(tag: selectTag, input: input, timeout: 30)
        guard selectResponse.contains("\(selectTag) OK") else {
            throw IMAPError.protocolError(selectResponse.lastLine ?? "SELECT INBOX failed")
        }
        // Fetch full body for this specific UID
        let fetchTag = nextTag()
        // Fetch headers (including Content-Type/Content-Transfer-Encoding for MIME decoding)
        // plus full body text (BODY.PEEK[TEXT])
        try write("\(fetchTag) UID FETCH \(uid) (UID FLAGS ENVELOPE BODY.PEEK[HEADER.FIELDS (Subject From Content-Type Content-Transfer-Encoding)] BODY.PEEK[TEXT])\r\n", output: output)
        let (fetchResponse, fetchRaw) = try readUntilTaggedRaw(tag: fetchTag, input: input, timeout: 60)
        let parsed = parseFetchedMessages(fetchResponse, rawData: fetchRaw)
        guard let fetched = parsed.first(where: { $0.uid == uid }) else {
            try logout(input: input, output: output)
            return nil
        }
        try logout(input: input, output: output)
        return fetched.detail(accountID: accountID, mailboxID: mailboxID, fallbackRecipient: fallbackRecipient)
    }

    /// Search emails using IMAP SEARCH command
    func search(usernames: [String], password: String, query: String) throws -> [String] {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let readStream, let writeStream else { throw IMAPError.connectionFailed("Cannot create socket streams for \(host):\(port)") }
        let input = readStream.takeRetainedValue() as InputStream
        let output = writeStream.takeRetainedValue() as OutputStream
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        let sslSettings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        input.setProperty(sslSettings, forKey: sslSettingsKey)
        output.setProperty(sslSettings, forKey: sslSettingsKey)
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        _ = try readUntilLine(input: input, timeout: 20)
        try authenticateWithPassword(usernames: usernames, password: password, input: input, output: output)
        return try searchInbox(input: input, output: output, query: query)
    }

    private func searchInbox(input: InputStream, output: OutputStream, query: String) throws -> [String] {
        let selectTag = nextTag()
        try write("\(selectTag) SELECT \"INBOX\"\r\n", output: output)
        let selectResponse = try readUntilTagged(tag: selectTag, input: input, timeout: 30)
        guard selectResponse.contains("\(selectTag) OK") else {
            throw IMAPError.protocolError(selectResponse.lastLine ?? "SELECT INBOX failed")
        }

        // IMAP SEARCH command
        let searchTag = nextTag()
        // Search in Subject, From, and body
        try write("\(searchTag) UID SEARCH OR SUBJECT \"\(query)\" OR FROM \"\(query)\" BODY \"\(query)\"\r\n", output: output)
        let searchResponse = try readUntilTagged(tag: searchTag, input: input, timeout: 60)

        // Parse SEARCH response: * SEARCH uid1 uid2 uid3 ...
        var uids: [String] = []
        let lines = searchResponse.components(separatedBy: "\r\n")
        for line in lines {
            if line.hasPrefix("* SEARCH") {
                let parts = line.components(separatedBy: " ")
                uids = Array(parts.dropFirst(2)) // drop "*" and "SEARCH"
            }
        }

        try logout(input: input, output: output)
        return uids
    }

    private func logout(input: InputStream, output: OutputStream) throws {
        let tag = nextTag()
        try write("\(tag) LOGOUT\r\n", output: output)
        _ = try? readUntilTagged(tag: tag, input: input, timeout: 10)
    }

    private func nextTag() -> String { "A\(Int.random(in: 1000...9999))" }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func write(_ string: String, output: OutputStream) throws {
        let bytes = Array(string.utf8)
        let written = bytes.withUnsafeBufferPointer { pointer in
            output.write(pointer.baseAddress!, maxLength: bytes.count)
        }
        guard written == bytes.count else { throw IMAPError.connectionFailed("Failed to write IMAP command") }
    }

    private func readUntilLine(input: InputStream, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let string = String(data: data, encoding: .utf8), string.contains("\r\n") { return string }
            } else if count < 0 {
                throw IMAPError.connectionFailed(input.streamError?.localizedDescription ?? "Read failed")
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw IMAPError.connectionFailed("Timed out waiting for IMAP greeting")
    }

    private func readUntilTaggedRaw(tag: String, input: InputStream, timeout: TimeInterval) throws -> (String, Data) {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Search for tag in raw bytes to avoid O(n²) String conversion on every read.
        // Tag marker: \r\n<tag> (space after tag signals tagged response line).
        let tagCRLF = "\r\n\(tag) ".data(using: .utf8)!
        let tagPrefix = "\(tag) ".data(using: .utf8)!
        while Date() < deadline {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                // Search the last 128 bytes + new data for the tag marker
                let searchRange: Int
                if data.count > 128 {
                    searchRange = data.count - min(data.count, 128 + count)
                } else {
                    searchRange = 0
                }
                let searchData = data.subdata(in: searchRange..<data.count)
                if searchData.range(of: tagCRLF) != nil || searchData.range(of: tagPrefix) != nil {
                    let string = String(decoding: data, as: Unicode.UTF8.self)
                    return (string, data)
                }
            } else if count < 0 {
                throw IMAPError.connectionFailed(input.streamError?.localizedDescription ?? "Read failed")
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw IMAPError.connectionFailed("Timed out waiting for IMAP response \(tag)")
    }

    private func readUntilTagged(tag: String, input: InputStream, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Same Data-level optimization as readUntilTaggedRaw
        let tagCRLF = "\r\n\(tag) ".data(using: .utf8)!
        let tagPrefix = "\(tag) ".data(using: .utf8)!
        while Date() < deadline {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                let searchRange = data.count > 128 ? data.count - min(data.count, 128 + count) : 0
                let searchData = data.subdata(in: searchRange..<data.count)
                if searchData.range(of: tagCRLF) != nil || searchData.range(of: tagPrefix) != nil {
                    return String(decoding: data, as: Unicode.UTF8.self)
                }
            } else if count < 0 {
                throw IMAPError.connectionFailed(input.streamError?.localizedDescription ?? "Read failed")
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw IMAPError.connectionFailed("Timed out waiting for IMAP response \(tag)")
    }
}

private struct ParsedHeaders {
    var messageID: String?
    var subject: String?
    var from: String?
    var to: String?
    var cc: String?
    var date: Date?
    var transferEncoding: String?

    init(raw: String, skipRFC2047: Bool = false) {
        let unfolded = raw.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
        self.messageID = unfolded.headerValue("Message-ID")
        if skipRFC2047 {
            // Raw UTF-8 header: content is already decoded, no RFC 2047 decode needed
            self.subject = unfolded.headerValue("Subject")?.nilIfEmpty
            self.from = unfolded.headerValue("From")
            self.to = unfolded.headerValue("To")
            self.cc = unfolded.headerValue("Cc")
        } else {
            self.subject = unfolded.headerValue("Subject")?.decodeRFC2047().nilIfEmpty
            self.from = unfolded.headerValue("From")?.decodeRFC2047()
            self.to = unfolded.headerValue("To")?.decodeRFC2047()
            self.cc = unfolded.headerValue("Cc")?.decodeRFC2047()
        }
        self.date = Self.parseDate(unfolded.headerValue("Date"))
        self.transferEncoding = unfolded.headerValue("Content-Transfer-Encoding")
    }

    static func extractCharset(from header: String) -> String? {
        let unfolded = header.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
        guard let contentType = unfolded.headerValue("Content-Type") else { return nil }
        if let charsetRange = contentType.range(of: #"charset="#, options: .caseInsensitive) {
            let afterCharset = contentType[charsetRange.upperBound...]
            if let endQuote = afterCharset.range(of: "\"") {
                return String(afterCharset[..<endQuote.lowerBound])
            }
            let endChars = CharacterSet(charactersIn: "; \t\r\n")
            var result = ""
            for char in afterCharset {
                if char.unicodeScalars.contains(where: { endChars.contains($0) }) { break }
                result.append(char)
            }
            return result.isEmpty ? nil : result
        }
        return nil
    }

    static func extractBoundary(from header: String) -> String? {
        let unfolded = header.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
        guard let contentType = unfolded.headerValue("Content-Type") else { return nil }
        if let boundaryRange = contentType.range(of: #"boundary="#, options: .caseInsensitive) {
            let afterBoundary = contentType[boundaryRange.upperBound...]
            if let startQuote = afterBoundary.range(of: "\"") {
                let afterQuote = afterBoundary[startQuote.upperBound...]
                if let endQuote = afterQuote.range(of: "\"") {
                    return String(afterQuote[..<endQuote.lowerBound])
                }
            }
            let endChars = CharacterSet(charactersIn: "; \t\r\n")
            var result = ""
            for char in afterBoundary {
                if char.unicodeScalars.contains(where: { endChars.contains($0) }) { break }
                result.append(char)
            }
            return result.isEmpty ? nil : result
        }
        return nil
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return nil
    }
}

private extension MailAddress {
    static func parse(_ value: String?) -> MailAddress? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let start = value.range(of: "<"), let end = value.range(of: ">", range: start.upperBound..<value.endIndex) {
            let name = String(value[..<start.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            let email = String(value[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MailAddress(name: name.nilIfEmpty, email: email)
        }
        return MailAddress(email: value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
    }

    static func parseList(_ value: String?) -> [MailAddress] {
        guard let value else { return [] }
        return value.split(separator: ",").compactMap { parse(String($0)) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var lastLine: String? {
        components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var normalizedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var htmlStripped: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    var mimeCleanedBody: String {
        var text = self
        let mimeHeaderPattern = #"(?m)^(Content-Type|Content-Transfer-Encoding|Mime-Version|Content-Disposition|Content-ID|X-)[^\n]*\n?"#
        text = text.replacingOccurrences(of: mimeHeaderPattern, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^--\S+\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^[A-Z]\d+ OK FETCH.*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodeRFC2047() -> String {
        let pattern = #"=\?([^?]+)\?([QBqb])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let nsString = self as NSString
        let allMatches = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
        guard !allMatches.isEmpty else { return self }
        var result = ""
        var lastEnd = 0
        for match in allMatches {
            let matchRange = match.range
            let gapStart = lastEnd
            let gapEnd = matchRange.location
            if gapStart < gapEnd {
                let gap = nsString.substring(with: NSRange(location: gapStart, length: gapEnd - gapStart))
                let isOnlyWhitespace = gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasAdjacentEncoded = gapStart > 0 && nsString.substring(with: NSRange(location: gapStart - 1, length: 1)) != " "
                if !isOnlyWhitespace {
                    result += gap
                }
            }
            guard let charsetRange = Range(match.range(at: 1), in: self),
                  let encodingRange = Range(match.range(at: 2), in: self),
                  let textRange = Range(match.range(at: 3), in: self) else {
                result += nsString.substring(with: matchRange)
                lastEnd = matchRange.location + matchRange.length
                continue
            }
            let charset = String(self[charsetRange]).lowercased()
            let encoding = String(self[encodingRange]).uppercased()
            let encodedText = String(self[textRange])
            if let decoded = RFC2047Codec.decodeOne(charset: charset, encoding: encoding, text: encodedText) {
                result += decoded
            } else {
                result += nsString.substring(with: matchRange)
            }
            lastEnd = matchRange.location + matchRange.length
        }
        if lastEnd < nsString.length {
            result += nsString.substring(from: lastEnd)
        }
        return result
    }

    func prefixString(_ count: Int) -> String {
        String(prefix(count))
    }

    func firstString(matching pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    func firstInt(matching pattern: String) -> Int? {
        firstString(matching: pattern).flatMap(Int.init)
    }

    func headerValue(_ name: String) -> String? {
        // Use anchorsMatchLines but NOT dotMatchesLineSeparators, so . does NOT match \n
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^\#(name):\s*(.+)$"#, options: [.anchorsMatchLines]) else { return nil }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RFC2047Codec {
    static func decodeOne(charset: String, encoding: String, text: String) -> String? {
        if encoding == "B" {
            guard let data = Data(base64Encoded: text) else { return nil }
            return decodeData(data, charset: charset)
        } else if encoding == "Q" {
            let cleaned = text.replacingOccurrences(of: "_", with: " ")
            var bytes = [UInt8]()
            var i = cleaned.startIndex
            while i < cleaned.endIndex {
                if cleaned[i] == "=",
                   i < cleaned.index(cleaned.endIndex, offsetBy: -2),
                   let byte = UInt8(cleaned[cleaned.index(after: i)...cleaned.index(i, offsetBy: 2)], radix: 16) {
                    bytes.append(byte)
                    i = cleaned.index(i, offsetBy: 3)
                } else {
                    if let scalar = cleaned[i].unicodeScalars.first, scalar.isASCII {
                        bytes.append(UInt8(scalar.value))
                    }
                    i = cleaned.index(after: i)
                }
            }
            return decodeData(Data(bytes), charset: charset)
        }
        return nil
    }

    static func decodeData(_ data: Data, charset: String) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let cfEncoding: CFStringEncoding
        switch charset {
        case "gb2312", "gbk", "gb18030": cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case "big5": cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        case "iso-2022-jp": cfEncoding = CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
        case "euc-jp": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)
        case "shift_jis", "shift-jis": cfEncoding = CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        case "euc-kr": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        default:
            return String(data: data, encoding: .ascii)
        }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }
}
