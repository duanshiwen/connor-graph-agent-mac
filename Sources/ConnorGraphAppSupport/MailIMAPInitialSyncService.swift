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

    public init(credentialStore: AppMailCredentialStore = AppMailCredentialStore(), messageLimit: Int = 25) {
        self.credentialStore = credentialStore
        self.messageLimit = messageLimit
    }

    public func sync(account originalAccount: MailAccount) async throws -> MailInitialSyncResult {
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
            let loginUsernames = candidateUsernames(email: email, provider: originalAccount.provider)
            let snapshot = try client.withPasswordSession(usernames: loginUsernames, password: rawCredential, messageLimit: messageLimit)
            let accountID = originalAccount.id
            let inboxID = MailMailboxID(rawValue: "\(accountID.rawValue)-inbox")
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

    private func candidateUsernames(email: String, provider: MailProviderKind) -> [String] {
        var usernames = [email]
        if provider == .genericIMAPSMTP || provider == .localFixture || provider == .jmap || provider == .gmail || provider == .microsoft365 {
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

private struct BlockingIMAPClient {
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
        var snippet: String
        var fallbackSequenceDate: Date

        func detail(accountID: MailAccountID, mailboxID: MailMailboxID, fallbackRecipient: MailAddress) -> MailMessageDetail {
            let headers = ParsedHeaders(raw: header)
            let messageID = headers.messageID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "imap-uid-\(uid)"
            let subject = headers.subject?.nilIfEmpty ?? "（无主题）"
            let from = MailAddress.parse(headers.from) ?? MailAddress(email: "unknown@example.com")
            let to = MailAddress.parseList(headers.to)
            let date = headers.date ?? fallbackSequenceDate
            let cleanSnippet = snippet.htmlStripped.normalizedWhitespace.prefixString(300)
            let summary = MailMessageSummary(
                id: MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-\(uid)"),
                accountID: accountID,
                mailboxID: mailboxID,
                threadID: MailThreadID(rawValue: messageID),
                subject: subject,
                from: from,
                to: to.isEmpty ? [fallbackRecipient] : to,
                cc: MailAddress.parseList(headers.cc),
                date: date,
                snippet: cleanSnippet.isEmpty ? "（无正文摘要）" : cleanSnippet,
                flags: MailMessageFlags(isRead: flags.localizedCaseInsensitiveContains("\\Seen"), isFlagged: flags.localizedCaseInsensitiveContains("\\Flagged"), isAnswered: flags.localizedCaseInsensitiveContains("\\Answered"), isDeleted: flags.localizedCaseInsensitiveContains("\\Deleted")),
                hasAttachments: header.localizedCaseInsensitiveContains("multipart/mixed")
            )
            let body = MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: cleanSnippet, byteCount: cleanSnippet.utf8.count, wasTruncated: snippet.utf8.count > cleanSnippet.utf8.count),
                redactedPreview: cleanSnippet,
                bodyHash: String(abs(snippet.hashValue))
            )
            return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: headers.messageID, rawHeaderHash: String(abs(header.hashValue))), body: body)
        }
    }

    var host: String
    var port: Int

    func withPasswordSession(usernames: [String], password: String, messageLimit: Int) throws -> Snapshot {
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
        return try fetchInboxSnapshot(input: input, output: output, messageLimit: messageLimit)
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

    private func fetchInboxSnapshot(input: InputStream, output: OutputStream, messageLimit: Int) throws -> Snapshot {
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
        let start = max(1, exists - max(1, messageLimit) + 1)
        let fetchTag = nextTag()
        try write("\(fetchTag) UID FETCH \(start):\(exists) (UID FLAGS BODY.PEEK[HEADER.FIELDS (MESSAGE-ID SUBJECT FROM TO CC DATE CONTENT-TYPE)] BODY.PEEK[TEXT]<0.1024>)\r\n", output: output)
        let fetchResponse = try readUntilTagged(tag: fetchTag, input: input, timeout: 60)
        try logout(input: input, output: output)
        let messages = parseFetchedMessages(fetchResponse)
        return Snapshot(exists: exists, unreadCount: statusUnseen ?? messages.filter { !$0.flags.localizedCaseInsensitiveContains("\\Seen") }.count, uidValidity: uidValidity, highestUID: messages.map(\.uid).compactMap(Int.init).max().map(String.init), messages: messages)
    }

    private func parseFetchedMessages(_ response: String) -> [FetchedMessage] {
        let chunks = response.components(separatedBy: "\r\n* ").map { $0.hasPrefix("* ") ? $0 : "* " + $0 }
        return chunks.compactMap { chunk in
            guard chunk.contains(" FETCH "), let uid = chunk.firstString(matching: #"UID\s+(\d+)"#) else { return nil }
            let flags = chunk.firstString(matching: #"FLAGS\s+\(([^)]*)\)"#) ?? ""
            let header = extractHeader(from: chunk)
            let body = extractBody(from: chunk, after: header)
            return FetchedMessage(uid: uid, flags: flags, header: header, snippet: body, fallbackSequenceDate: Date())
        }.sorted { (Int($0.uid) ?? 0) > (Int($1.uid) ?? 0) }
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

    private func readUntilTagged(tag: String, input: InputStream, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date() < deadline {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let string = String(data: data, encoding: .utf8), string.contains("\r\n\(tag) ") || string.hasPrefix("\(tag) ") { return string }
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

    init(raw: String) {
        let unfolded = raw.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
        self.messageID = unfolded.headerValue("Message-ID")
        self.subject = unfolded.headerValue("Subject")
        self.from = unfolded.headerValue("From")
        self.to = unfolded.headerValue("To")
        self.cc = unfolded.headerValue("Cc")
        self.date = Self.parseDate(unfolded.headerValue("Date"))
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
        firstString(matching: #"(?m)^\#(name):\s*(.+)$"#)
    }
}
