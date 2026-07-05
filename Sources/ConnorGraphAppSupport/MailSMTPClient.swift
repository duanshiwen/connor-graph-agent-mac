import Foundation
import ConnorGraphCore

public struct MailSMTPSendRequest: Sendable, Equatable {
    public var endpoint: MailServerEndpoint
    public var username: String
    public var password: String
    public var from: MailAddress
    public var recipients: [MailAddress]
    public var rawMessage: String
    public var envelopeHash: String
    public var timeoutSeconds: TimeInterval

    public init(
        endpoint: MailServerEndpoint,
        username: String,
        password: String,
        from: MailAddress,
        recipients: [MailAddress],
        rawMessage: String,
        envelopeHash: String,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.from = from
        self.recipients = recipients
        self.rawMessage = rawMessage
        self.envelopeHash = envelopeHash
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct MailSMTPSendResponse: Sendable, Equatable, Codable {
    public var providerMessageID: String
    public var acceptedRecipients: [String]
    public var sentAt: Date

    public init(providerMessageID: String, acceptedRecipients: [String] = [], sentAt: Date = Date()) {
        self.providerMessageID = providerMessageID
        self.acceptedRecipients = acceptedRecipients
        self.sentAt = sentAt
    }
}

public enum MailSMTPClientError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidEndpoint(String)
    case missingRecipients
    case unsupportedSecurity(String)
    case connectionFailed(String)
    case startTLSUnavailable(String)
    case authenticationFailed(String)
    case networkSendNotAvailable(String)
    case smtpRejected(String)

    public var description: String {
        switch self {
        case .invalidEndpoint(let value): "Invalid SMTP endpoint: \(value)"
        case .missingRecipients: "SMTP send requires at least one recipient"
        case .unsupportedSecurity(let value): "Unsupported SMTP security: \(value)"
        case .connectionFailed(let value): "SMTP connection failed: \(value)"
        case .startTLSUnavailable(let value): "SMTP STARTTLS unavailable: \(value)"
        case .authenticationFailed(let value): "SMTP authentication failed: \(value)"
        case .networkSendNotAvailable(let value): "SMTP network send unavailable: \(value)"
        case .smtpRejected(let value): "SMTP rejected send: \(value)"
        }
    }
}

public protocol MailSMTPClient: Sendable {
    func send(_ request: MailSMTPSendRequest) async throws -> MailSMTPSendResponse
}

public actor FakeMailSMTPClient: MailSMTPClient {
    public private(set) var requests: [MailSMTPSendRequest] = []
    private let response: MailSMTPSendResponse
    private let error: Error?

    public init(response: MailSMTPSendResponse = MailSMTPSendResponse(providerMessageID: "fake-smtp-message-id"), error: Error? = nil) {
        self.response = response
        self.error = error
    }

    public func send(_ request: MailSMTPSendRequest) async throws -> MailSMTPSendResponse {
        requests.append(request)
        if let error { throw error }
        if request.recipients.isEmpty { throw MailSMTPClientError.missingRecipients }
        return MailSMTPSendResponse(
            providerMessageID: response.providerMessageID,
            acceptedRecipients: response.acceptedRecipients.isEmpty ? request.recipients.map(\.email) : response.acceptedRecipients,
            sentAt: response.sentAt
        )
    }
}

/// Commercial SMTP client boundary. The full protocol exchange is intentionally isolated behind
/// this type so MailRuntime never exposes credentials to LLM/tool JSON. Phase B establishes the
/// network boundary and validation; Phase C wires it into the send lifecycle.
public struct NetworkMailSMTPClient: MailSMTPClient {
    public init() {}

    public func send(_ request: MailSMTPSendRequest) async throws -> MailSMTPSendResponse {
        guard request.endpoint.protocolKind == .smtp else {
            throw MailSMTPClientError.invalidEndpoint("\(request.endpoint.protocolKind.rawValue)")
        }
        guard !request.endpoint.host.isEmpty, request.endpoint.port > 0 else {
            throw MailSMTPClientError.invalidEndpoint("\(request.endpoint.host):\(request.endpoint.port)")
        }
        guard !request.recipients.isEmpty else { throw MailSMTPClientError.missingRecipients }
        guard request.endpoint.security == .tls || request.endpoint.security == .startTLS else {
            throw MailSMTPClientError.unsupportedSecurity(request.endpoint.security.rawValue)
        }

        // Network.framework SMTP exchange will be completed in the runtime integration phase with
        // fake-server protocol tests. Until then, this production client refuses to claim a send.
        throw MailSMTPClientError.networkSendNotAvailable("SMTP protocol exchange is not enabled until MailRuntime wires the tested transport path")
    }
}
