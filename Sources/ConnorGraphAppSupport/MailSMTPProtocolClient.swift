import Foundation

public protocol MailSMTPConnection: Sendable {
    func readResponse(timeout: TimeInterval) async throws -> String
    func writeLine(_ line: String) async throws
    func startTLS(host: String, timeout: TimeInterval) async throws
    func close() async
}

public struct MailSMTPProtocolClient: Sendable {
    private let localHostname: String

    public init(localHostname: String = "localhost") {
        self.localHostname = localHostname
    }

    public func send(_ request: MailSMTPSendRequest, over connection: any MailSMTPConnection) async throws -> MailSMTPSendResponse {
        defer { Task { await connection.close() } }

        let greeting = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(greeting, prefix: "220", failure: .connectionFailed("SMTP greeting rejected: \(greeting)"))

        var capabilities = try await ehlo(connection: connection, timeout: request.timeoutSeconds)
        if request.endpoint.security == .startTLS {
            guard capabilities.contains("STARTTLS") else {
                throw MailSMTPClientError.startTLSUnavailable("\(request.endpoint.host):\(request.endpoint.port)")
            }
            try await connection.writeLine("STARTTLS")
            let startTLSResponse = try await connection.readResponse(timeout: request.timeoutSeconds)
            try require(startTLSResponse, prefix: "220", failure: .connectionFailed("STARTTLS failed: \(startTLSResponse)"))
            try await connection.startTLS(host: request.endpoint.host, timeout: request.timeoutSeconds)
            capabilities = try await ehlo(connection: connection, timeout: request.timeoutSeconds)
        }

        try await authenticate(request: request, connection: connection)
        try await sendEnvelope(request: request, connection: connection)
        let finalResponse = try await sendData(request: request, connection: connection)
        try await connection.writeLine("QUIT")
        _ = try? await connection.readResponse(timeout: min(request.timeoutSeconds, 10))

        return MailSMTPSendResponse(
            providerMessageID: providerMessageID(from: finalResponse, fallback: request.envelopeHash),
            acceptedRecipients: request.recipients.map(\.email)
        )
    }

    private func ehlo(connection: any MailSMTPConnection, timeout: TimeInterval) async throws -> Set<String> {
        try await connection.writeLine("EHLO \(localHostname)")
        let response = try await connection.readResponse(timeout: timeout)
        try require(response, prefix: "250", failure: .connectionFailed("EHLO failed: \(response)"))
        return Set(parseCapabilities(response).map { $0.uppercased() })
    }

    private func authenticate(request: MailSMTPSendRequest, connection: any MailSMTPConnection) async throws {
        try await connection.writeLine("AUTH LOGIN")
        let auth = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(auth, prefix: "334", failure: .authenticationFailed("AUTH LOGIN failed: \(auth)"))

        try await connection.writeLine(Data(request.username.utf8).base64EncodedString())
        let username = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(username, prefix: "334", failure: .authenticationFailed("Username rejected: \(username)"))

        try await connection.writeLine(Data(request.password.utf8).base64EncodedString())
        let password = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(password, prefix: "235", failure: .authenticationFailed("Password rejected: \(password)"))
    }

    private func sendEnvelope(request: MailSMTPSendRequest, connection: any MailSMTPConnection) async throws {
        try await connection.writeLine("MAIL FROM:<\(request.from.email)>")
        let from = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(from, prefix: "250", failure: .smtpRejected("MAIL FROM failed: \(from)"))

        for recipient in request.recipients {
            try await connection.writeLine("RCPT TO:<\(recipient.email)>")
            let rcpt = try await connection.readResponse(timeout: request.timeoutSeconds)
            try require(rcpt, prefix: "250", failure: .smtpRejected("RCPT TO failed for \(recipient.email): \(rcpt)"))
        }
    }

    private func sendData(request: MailSMTPSendRequest, connection: any MailSMTPConnection) async throws -> String {
        try await connection.writeLine("DATA")
        let data = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(data, prefix: "354", failure: .smtpRejected("DATA failed: \(data)"))

        try await connection.writeLine(request.rawMessage)
        try await connection.writeLine(".")
        let final = try await connection.readResponse(timeout: request.timeoutSeconds)
        try require(final, prefix: "250", failure: .smtpRejected("Message body rejected: \(final)"))
        return final
    }

    private func require(_ response: String, prefix: String, failure: MailSMTPClientError) throws {
        guard response.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) else { throw failure }
    }

    private func parseCapabilities(_ response: String) -> [String] {
        response
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.count >= 4 else { return nil }
                let index = line.index(line.startIndex, offsetBy: 4)
                return String(line[index...].split(separator: " ").first ?? "")
            }
            .filter { !$0.isEmpty }
    }

    private func providerMessageID(from response: String, fallback: String) -> String {
        if let range = response.range(of: "Queued as ", options: [.caseInsensitive]) {
            return String(response[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "smtp-\(fallback.prefix(12))-\(Int(Date().timeIntervalSince1970))"
    }
}
