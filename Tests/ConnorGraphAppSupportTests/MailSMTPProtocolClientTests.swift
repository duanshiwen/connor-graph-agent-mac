import Foundation
import Darwin
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

/// 只接受 TCP 连接但从不响应任何数据的本地服务器，用于验证 SMTP 读超时。
private final class SilentTCPServer: @unchecked Sendable {
    let port: Int
    private let fd: Int32

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MailSMTPClientError.connectionFailed("socket creation failed") }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else { close(fd); throw MailSMTPClientError.connectionFailed("bind failed") }
        guard listen(fd, 1) == 0 else { close(fd); throw MailSMTPClientError.connectionFailed("listen failed") }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        self.fd = fd
        self.port = Int(bound.sin_port.bigEndian)
    }

    /// 接受一个连接并保持打开但不回包（阻塞直到连接到达）。
    func acceptSilently() {
        var addr = sockaddr()
        var len = socklen_t(MemoryLayout<sockaddr>.size)
        _ = withUnsafeMutablePointer(to: &addr) { accept(fd, $0, &len) }
        Thread.sleep(forTimeInterval: 30)
    }

    deinit { close(fd) }
}

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
    /// 回归测试：服务器接受连接后静默不回包时，readResponse 必须在限时内抛错，
    /// 而不是因 InputStream.read 阻塞而无限卡住（此前会导致发送邮件永久挂起）。
    @Test func streamReadTimesOutWhenServerStaysSilent() async throws {
        let server = try SilentTCPServer()
        let connection = MailSMTPStreamConnection(host: "127.0.0.1", port: server.port)
        let acceptTask = Task.detached { server.acceptSilently() }
        defer { acceptTask.cancel() }

        try await connection.connect(timeout: 5)
        let started = Date()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { _ = try await connection.readResponse(timeout: 1) }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw MailSMTPClientError.connectionFailed("readResponse blocked beyond deadline")
                }
                do {
                    try await group.next()
                    group.cancelAll()
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
            Issue.record("readResponse should have timed out")
        } catch let error as MailSMTPClientError {
            let elapsed = Date().timeIntervalSince(started)
            #expect(elapsed < 7, "expected fast timeout, took \(elapsed)s")
            _ = error
        }
        await connection.close()
    }


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
