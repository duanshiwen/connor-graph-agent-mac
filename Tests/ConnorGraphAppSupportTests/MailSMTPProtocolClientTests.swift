import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private actor ScriptedSMTPConnection: MailSMTPConnection {
    private var responses: [String]
    private(set) var writtenLines: [String] = []
    private(set) var didStartTLS = false

    init(responses: [String]) {
        self.responses = responses
    }

    func readResponse(timeout: TimeInterval) async throws -> String {
        guard !responses.isEmpty else { throw MailSMTPClientError.connectionFailed("No scripted SMTP response") }
        return responses.removeFirst()
    }

    func writeLine(_ line: String) async throws {
        writtenLines.append(line)
    }

    func startTLS(host: String, timeout: TimeInterval) async throws {
        didStartTLS = true
    }

    func close() async {}

    func transcript() -> [String] { writtenLines }
    func tlsStarted() -> Bool { didStartTLS }
}

@Suite("Mail SMTP Protocol Client Tests")
struct MailSMTPProtocolClientTests {
    @Test func startTLSAuthLoginSendUsesApprovedRawMessageAndReEHLOsAfterUpgrade() async throws {
        let connection = ScriptedSMTPConnection(responses: [
            "220 smtp.example.com ESMTP ready",
            "250-smtp.example.com\r\n250-STARTTLS\r\n250 AUTH LOGIN",
            "220 Ready to start TLS",
            "250-smtp.example.com\r\n250 AUTH LOGIN",
            "334 VXNlcm5hbWU6",
            "334 UGFzc3dvcmQ6",
            "235 Authentication successful",
            "250 Sender OK",
            "250 Recipient OK",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 Queued as provider-123",
            "221 Bye"
        ])
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            username: "user@example.com",
            password: "secret",
            from: MailAddress(email: "user@example.com"),
            recipients: [MailAddress(email: "to@example.com")],
            rawMessage: "Subject: Approved\r\n\r\nHello",
            envelopeHash: "hash-123"
        )

        let response = try await MailSMTPProtocolClient().send(request, over: connection)

        #expect(response.providerMessageID == "provider-123")
        #expect(response.acceptedRecipients == ["to@example.com"])
        #expect(await connection.tlsStarted())
        #expect(await connection.transcript() == [
            "EHLO localhost",
            "STARTTLS",
            "EHLO localhost",
            "AUTH LOGIN",
            "dXNlckBleGFtcGxlLmNvbQ==",
            "c2VjcmV0",
            "MAIL FROM:<user@example.com>",
            "RCPT TO:<to@example.com>",
            "DATA",
            "Subject: Approved\r\n\r\nHello",
            ".",
            "QUIT"
        ])
    }

    @Test func startTLSEndpointRequiresAdvertisedCapability() async throws {
        let connection = ScriptedSMTPConnection(responses: [
            "220 smtp.example.com ESMTP ready",
            "250-smtp.example.com\r\n250 AUTH LOGIN"
        ])
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            username: "user@example.com",
            password: "secret",
            from: MailAddress(email: "user@example.com"),
            recipients: [MailAddress(email: "to@example.com")],
            rawMessage: "Subject: Approved\r\n\r\nHello",
            envelopeHash: "hash-123"
        )

        await #expect(throws: MailSMTPClientError.startTLSUnavailable("smtp.example.com:587")) {
            _ = try await MailSMTPProtocolClient().send(request, over: connection)
        }
    }

    @Test func networkClientUsesInjectedTransportInsteadOfPlaceholderFailure() async throws {
        let connection = ScriptedSMTPConnection(responses: [
            "220 smtp.example.com ESMTP ready",
            "250-smtp.example.com\r\n250-STARTTLS\r\n250 AUTH LOGIN",
            "220 Ready to start TLS",
            "250-smtp.example.com\r\n250 AUTH LOGIN",
            "334 VXNlcm5hbWU6",
            "334 UGFzc3dvcmQ6",
            "235 Authentication successful",
            "250 Sender OK",
            "250 Recipient OK",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 Queued as provider-456",
            "221 Bye"
        ])
        let client = NetworkMailSMTPClient(connectionFactory: { _ in connection })
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            username: "user@example.com",
            password: "secret",
            from: MailAddress(email: "user@example.com"),
            recipients: [MailAddress(email: "to@example.com")],
            rawMessage: "Subject: Approved\r\n\r\nHello",
            envelopeHash: "hash-456"
        )

        let response = try await client.send(request)

        #expect(response.providerMessageID == "provider-456")
        #expect(await connection.transcript().contains("DATA"))
    }

    @Test func networkClientRejectsImplicitTLSWithActionableGuidance() async throws {
        let client = NetworkMailSMTPClient(connectionFactory: { _ in
            Issue.record("implicit TLS should fail before creating a connection")
            return ScriptedSMTPConnection(responses: [])
        })
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 465, security: .tls, protocolKind: .smtp),
            username: "user@example.com",
            password: "secret",
            from: MailAddress(email: "user@example.com"),
            recipients: [MailAddress(email: "to@example.com")],
            rawMessage: "Subject: Approved\r\n\r\nHello",
            envelopeHash: "hash-456"
        )

        await #expect(throws: MailSMTPClientError.unsupportedSecurity("tls; use SMTP STARTTLS on port 587")) {
            _ = try await client.send(request)
        }
    }

    @Test func smtpErrorsExposeActionableLocalizedDescriptions() {
        #expect(MailSMTPClientError.startTLSUnavailable("smtp.example.com:587").localizedDescription.contains("port 587"))
        #expect(MailSMTPClientError.authenticationFailed("535 auth failed").localizedDescription.contains("authorization code"))
    }

    @Test func rejectedRecipientReportsSMTPRejection() async throws {
        let connection = ScriptedSMTPConnection(responses: [
            "220 smtp.example.com ESMTP ready",
            "250-smtp.example.com\r\n250-STARTTLS\r\n250 AUTH LOGIN",
            "220 Ready to start TLS",
            "250-smtp.example.com\r\n250 AUTH LOGIN",
            "334 VXNlcm5hbWU6",
            "334 UGFzc3dvcmQ6",
            "235 Authentication successful",
            "250 Sender OK",
            "550 Mailbox unavailable"
        ])
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            username: "user@example.com",
            password: "secret",
            from: MailAddress(email: "user@example.com"),
            recipients: [MailAddress(email: "bad@example.com")],
            rawMessage: "Subject: Approved\r\n\r\nHello",
            envelopeHash: "hash-123"
        )

        await #expect(throws: MailSMTPClientError.smtpRejected("RCPT TO failed for bad@example.com: 550 Mailbox unavailable")) {
            _ = try await MailSMTPProtocolClient().send(request, over: connection)
        }
    }
}
