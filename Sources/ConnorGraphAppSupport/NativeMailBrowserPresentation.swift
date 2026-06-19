import Foundation
import ConnorGraphCore

public enum NativeMailBrowserEmptyState: String, Codable, Sendable, Equatable, Hashable {
    case noAccounts
    case noMailboxes
    case noMessages
    case searchNoResults
    case noSelection
}

public enum MailAccountProviderPreset: String, CaseIterable, Codable, Sendable, Equatable, Hashable, Identifiable {
    case apple
    case microsoft
    case qq
    case netease
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apple: "Apple iCloud"
        case .microsoft: "Microsoft Outlook / 365"
        case .qq: "QQ 邮箱"
        case .netease: "网易 163 / 126"
        case .other: "其他 IMAP/SMTP"
        }
    }

    public var subtitle: String {
        switch self {
        case .apple: "iCloud Mail，使用 App 专用密码"
        case .microsoft: "优先 Microsoft 登录，IMAP/SMTP 作为高级选项"
        case .qq: "需要先开启 IMAP/SMTP，并使用 16 位授权码"
        case .netease: "适用于 163/126，推荐 IMAP 与客户端授权码"
        case .other: "手动填写收件和发件服务器"
        }
    }

    public var incomingHost: String {
        switch self {
        case .apple: "imap.mail.me.com"
        case .microsoft: "outlook.office365.com"
        case .qq: "imap.qq.com"
        case .netease: "imap.163.com"
        case .other: ""
        }
    }

    public var incomingPort: Int {
        switch self {
        case .apple, .microsoft, .qq, .netease: 993
        case .other: 993
        }
    }

    public var outgoingHost: String {
        switch self {
        case .apple: "smtp.mail.me.com"
        case .microsoft: "smtp.office365.com"
        case .qq: "smtp.qq.com"
        case .netease: "smtp.163.com"
        case .other: ""
        }
    }

    public var outgoingPort: Int {
        switch self {
        case .apple, .microsoft: 587
        case .qq, .netease: 465
        case .other: 587
        }
    }

    public var incomingSecurity: MailConnectionSecurity { .tls }

    public var outgoingSecurity: MailConnectionSecurity {
        switch self {
        case .apple, .microsoft: .startTLS
        case .qq, .netease: .tls
        case .other: .startTLS
        }
    }

    public var authMode: MailAuthMode {
        switch self {
        case .microsoft: .oauth2
        case .apple, .qq, .netease: .appPassword
        case .other: .appPassword
        }
    }

    public var guidance: String {
        switch self {
        case .apple:
            "Apple iCloud Mail 使用 imap.mail.me.com:993 和 smtp.mail.me.com:587。请使用 Apple 账户生成的 App 专用密码，不要输入 Apple ID 主密码。"
        case .microsoft:
            "Microsoft 账户建议优先使用 Microsoft 登录 / OAuth / Graph。手动 IMAP/SMTP 仅作为高级选项，常见发件端口为 587 + STARTTLS。"
        case .qq:
            "QQ 邮箱默认关闭 POP3/SMTP/IMAP。请先在网页版设置中开启服务，第三方客户端必须使用 16 位授权码。"
        case .netease:
            "网易 163/126 需要在网页版设置中开启 POP/SMTP/IMAP 客户端协议。推荐 IMAP，并为 Connor 单独生成客户端授权码。"
        case .other:
            "适用于企业邮箱或自定义 IMAP/SMTP 服务。请填写服务商提供的主机、端口、安全类型和认证方式。"
        }
    }
}

public struct NativeMailBrowserPresentation: Sendable, Equatable {
    public var accounts: [MailAccount]
    public var mailboxes: [MailMailbox]
    public var messages: [MailMessageSummary]

    public init(accounts: [MailAccount], mailboxes: [MailMailbox], messages: [MailMessageSummary]) {
        self.accounts = accounts
        self.mailboxes = mailboxes
        self.messages = messages
    }

    public func account(id: MailAccountID?) -> MailAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    public func mailbox(id: MailMailboxID?) -> MailMailbox? {
        guard let id else { return nil }
        return mailboxes.first { $0.id == id }
    }

    public func message(id: MailMessageID?) -> MailMessageSummary? {
        guard let id else { return nil }
        return messages.first { $0.id == id }
    }

    public func mailboxes(accountID: MailAccountID?) -> [MailMailbox] {
        guard let accountID else { return [] }
        return mailboxes.filter { $0.accountID == accountID }
    }

    public func messages(accountID: MailAccountID?, mailboxID: MailMailboxID?, query: String) -> [MailMessageSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return messages.filter { message in
            if let accountID, message.accountID != accountID { return false }
            if let mailboxID, message.mailboxID != mailboxID { return false }
            guard !normalized.isEmpty else { return true }
            return message.subject.lowercased().contains(normalized)
                || message.snippet.lowercased().contains(normalized)
                || message.from.email.lowercased().contains(normalized)
                || (message.from.name?.lowercased().contains(normalized) ?? false)
        }
        .sorted { lhs, rhs in lhs.date > rhs.date }
    }

    public var totalMessageCount: Int {
        let mailboxMessageCount = mailboxes.reduce(0) { $0 + $1.status.messageCount }
        return max(mailboxMessageCount, messages.count)
    }

    public var totalUnreadCount: Int {
        mailboxes.reduce(0) { $0 + $1.status.unreadCount }
    }

    public func defaultAccountID() -> MailAccountID? {
        accounts.first?.id
    }

    public func defaultMailboxID(for accountID: MailAccountID?) -> MailMailboxID? {
        mailboxes(accountID: accountID).first?.id
    }

    public func defaultMessageID(accountID: MailAccountID?, mailboxID: MailMailboxID?) -> MailMessageID? {
        messages(accountID: accountID, mailboxID: mailboxID, query: "").first?.id
    }

    public func emptyState(forQuery query: String) -> NativeMailBrowserEmptyState {
        if accounts.isEmpty { return .noAccounts }
        if mailboxes.isEmpty { return .noMailboxes }
        if messages.isEmpty { return .noMessages }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .searchNoResults }
        return .noSelection
    }
}

public extension NativeMailBrowserPresentation {
    static let empty = NativeMailBrowserPresentation(accounts: [], mailboxes: [], messages: [])
}
