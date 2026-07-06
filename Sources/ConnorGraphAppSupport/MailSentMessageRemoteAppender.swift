import Foundation
import ConnorGraphCore

public struct MailRemoteAppendSentResult: Sendable, Equatable {
    public var mailboxPath: String

    public init(mailboxPath: String) {
        self.mailboxPath = mailboxPath
    }
}

public protocol MailSentMessageRemoteAppender: Sendable {
    func appendSentMessage(
        account: MailAccount,
        password: String,
        rawMessage: String,
        mailboxPath: String,
        sentAt: Date
    ) async throws -> MailRemoteAppendSentResult
}

public struct NoopMailSentMessageRemoteAppender: MailSentMessageRemoteAppender {
    public init() {}

    public func appendSentMessage(account: MailAccount, password: String, rawMessage: String, mailboxPath: String, sentAt: Date) async throws -> MailRemoteAppendSentResult {
        MailRemoteAppendSentResult(mailboxPath: mailboxPath)
    }
}

public struct NetworkMailSentMessageRemoteAppender: MailSentMessageRemoteAppender {
    public init() {}

    public func appendSentMessage(account: MailAccount, password: String, rawMessage: String, mailboxPath: String, sentAt: Date) async throws -> MailRemoteAppendSentResult {
        guard let endpoint = account.incoming, endpoint.protocolKind == .imap else {
            throw MailRuntimeError.unsupportedNetworkOperation("Mail account has no incoming IMAP endpoint for remote Sent APPEND: \(account.id.rawValue)")
        }
        guard endpoint.security == .tls else {
            throw MailRuntimeError.unsupportedNetworkOperation("Unsupported IMAP security for remote Sent APPEND: \(endpoint.security.rawValue)")
        }
        guard let email = account.identities.first?.address.email, !email.isEmpty else {
            throw MailRuntimeError.unsupportedNetworkOperation("Missing mail identity address for remote Sent APPEND: \(account.id.rawValue)")
        }
        let usernames = MailIMAPInitialSyncService.candidateUsernames(email: email, provider: account.provider)
        let client = BlockingIMAPClient(host: endpoint.host, port: endpoint.port)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try client.appendMessage(usernames: usernames, password: password, mailboxPath: mailboxPath, rawMessage: rawMessage, internalDate: sentAt)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return MailRemoteAppendSentResult(mailboxPath: mailboxPath)
    }
}
