import Foundation
import Security
import ConnorGraphCore

/// SMTP client for sending emails. Supports AUTH LOGIN with TLS.
public struct MailSMTPSender: Sendable {
    public var credentialStore: AppMailCredentialStore

    public init(credentialStore: AppMailCredentialStore = AppMailCredentialStore()) {
        self.credentialStore = credentialStore
    }

    /// Send an email via SMTP
    public func send(
        account: MailAccount,
        subject: String,
        body: String,
        to: [MailAddress],
        cc: [MailAddress] = [],
        bcc: [MailAddress] = [],
        from: MailAddress? = nil
    ) async throws {
        guard let outgoing = account.outgoing else {
            throw SMTPError.missingConfiguration("缺少 SMTP 发件服务器配置")
        }
        guard outgoing.protocolKind == .smtp else {
            throw SMTPError.missingConfiguration("发件服务器不是 SMTP")
        }
        guard let binding = account.credentialBinding,
              let credential = try credentialStore.readCredential(binding: binding),
              !credential.isEmpty else {
            throw SMTPError.authenticationFailed("缺少凭据")
        }
        let sender = from ?? account.identities.first?.address ?? MailAddress(email: "unknown@example.com")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let client = BlockingSMTPClient(host: outgoing.host, port: outgoing.port, security: outgoing.security)
                    try client.send(
                        username: binding.accountName.components(separatedBy: ":").last ?? sender.email,
                        password: credential,
                        from: sender,
                        to: to,
                        cc: cc,
                        bcc: bcc,
                        subject: subject,
                        body: body
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public enum SMTPError: Error, LocalizedError {
    case missingConfiguration(String)
    case authenticationFailed(String)
    case connectionFailed(String)
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let msg): return msg
        case .authenticationFailed(let msg): return msg
        case .connectionFailed(let msg): return msg
        case .sendFailed(let msg): return msg
        }
    }
}

/// Blocking SMTP client using raw sockets. Supports AUTH LOGIN with TLS.
private class BlockingSMTPClient {
    let host: String
    let port: Int
    let security: MailConnectionSecurity

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var tagCounter = 0

    init(host: String, port: Int, security: MailConnectionSecurity) {
        self.host = host
        self.port = port
        self.security = security
    }

    func send(
        username: String,
        password: String,
        from: MailAddress,
        to: [MailAddress],
        cc: [MailAddress],
        bcc: [MailAddress],
        subject: String,
        body: String
    ) throws {
        // Connect
        var inStream: InputStream?
        var outStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inStream, outputStream: &outStream)
        guard let input = inStream, let output = outStream else {
            throw SMTPError.connectionFailed("无法连接到 \(host):\(port)")
        }

        // SMTP only supports STARTTLS (port 587), not implicit TLS (port 465)
        // Port 465 is deprecated by IANA
        guard security == .startTLS else {
            throw SMTPError.connectionFailed("SMTP 仅支持 STARTTLS (端口 587)，不支持隐式 TLS")
        }

        input.open()
        output.open()

        self.inputStream = input
        self.outputStream = output

        defer {
            input.close()
            output.close()
        }

        // Read greeting
        let greeting = try readResponse(timeout: 30)
        guard greeting.hasPrefix("220") else {
            throw SMTPError.connectionFailed("SMTP 服务器拒绝连接: \(greeting)")
        }

        // EHLO
        try write("EHLO \(host)")
        let ehloResponse = try readResponse(timeout: 30)
        guard ehloResponse.hasPrefix("250") else {
            throw SMTPError.connectionFailed("EHLO 失败: \(ehloResponse)")
        }

        // STARTTLS if needed
        if security == .startTLS {
            try write("STARTTLS")
            let starttlsResponse = try readResponse(timeout: 30)
            guard starttlsResponse.hasPrefix("220") else {
                throw SMTPError.connectionFailed("STARTTLS 失败: \(starttlsResponse)")
            }
            // Upgrade to TLS
            let sslSettings: [String: Any] = [
                kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelTLSv1,
                kCFStreamSSLPeerName as String: host,
                kCFStreamSSLValidatesCertificateChain as String: true
            ]
            input.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))
            output.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))

            // Re-EHLO after STARTTLS
            try write("EHLO \(host)")
            let ehlo2Response = try readResponse(timeout: 30)
            guard ehlo2Response.hasPrefix("250") else {
                throw SMTPError.connectionFailed("EHLO after STARTTLS 失败: \(ehlo2Response)")
            }
        }

        // AUTH LOGIN
        try write("AUTH LOGIN")
        let authResponse = try readResponse(timeout: 30)
        guard authResponse.hasPrefix("334") else {
            throw SMTPError.authenticationFailed("AUTH LOGIN 失败: \(authResponse)")
        }

        // Send username (base64)
        let usernameB64 = Data(username.utf8).base64EncodedString()
        try write(usernameB64)
        let userResponse = try readResponse(timeout: 30)
        guard userResponse.hasPrefix("334") else {
            throw SMTPError.authenticationFailed("用户名验证失败: \(userResponse)")
        }

        // Send password (base64)
        let passwordB64 = Data(password.utf8).base64EncodedString()
        try write(passwordB64)
        let passResponse = try readResponse(timeout: 30)
        guard passResponse.hasPrefix("235") else {
            throw SMTPError.authenticationFailed("密码验证失败: \(passResponse)")
        }

        // MAIL FROM
        try write("MAIL FROM:<\(from.email)>")
        let fromResponse = try readResponse(timeout: 30)
        guard fromResponse.hasPrefix("250") else {
            throw SMTPError.sendFailed("MAIL FROM 失败: \(fromResponse)")
        }

        // RCPT TO
        let allRecipients = to + cc + bcc
        for recipient in allRecipients {
            try write("RCPT TO:<\(recipient.email)>")
            let rcptResponse = try readResponse(timeout: 30)
            guard rcptResponse.hasPrefix("250") else {
                throw SMTPError.sendFailed("RCPT TO 失败 (\(recipient.email)): \(rcptResponse)")
            }
        }

        // DATA
        try write("DATA")
        let dataResponse = try readResponse(timeout: 30)
        guard dataResponse.hasPrefix("354") else {
            throw SMTPError.sendFailed("DATA 失败: \(dataResponse)")
        }

        // Build email content
        let messageID = "<\(Int(Date().timeIntervalSince1970)).\(UUID().uuidString)@\(host)>"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateStr = dateFormatter.string(from: Date())

        var emailContent = ""
        emailContent += "From: \(from.name.map { "\($0) <\(from.email)>" } ?? from.email)\r\n"
        emailContent += "To: \(to.map { a in a.name.map { n in "\(n) <\(a.email)>" } ?? a.email }.joined(separator: ", "))\r\n"
        if !cc.isEmpty {
            emailContent += "Cc: \(cc.map { a in a.name.map { n in "\(n) <\(a.email)>" } ?? a.email }.joined(separator: ", "))\r\n"
        }
        emailContent += "Date: \(dateStr)\r\n"
        emailContent += "Message-ID: \(messageID)\r\n"
        emailContent += "Subject: \(subject)\r\n"
        emailContent += "MIME-Version: 1.0\r\n"
        emailContent += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
        emailContent += "Content-Transfer-Encoding: base64\r\n"
        emailContent += "\r\n"
        emailContent += Data(body.utf8).base64EncodedString(options: [.lineLength76Characters])
        emailContent += "\r\n."

        try write(emailContent)
        let sendResponse = try readResponse(timeout: 60)
        guard sendResponse.hasPrefix("250") else {
            throw SMTPError.sendFailed("发送失败: \(sendResponse)")
        }

        // QUIT
        try write("QUIT")
        _ = try? readResponse(timeout: 10)
    }

    private func write(_ string: String) throws {
        let data = Array("\(string)\r\n".utf8)
        guard let outputStream else { throw SMTPError.connectionFailed("连接已关闭") }
        let written = data.withUnsafeBufferPointer { ptr in
            outputStream.write(ptr.baseAddress!, maxLength: data.count)
        }
        guard written == data.count else { throw SMTPError.connectionFailed("写入失败") }
    }

    private func readResponse(timeout: TimeInterval) throws -> String {
        guard let inputStream else { throw SMTPError.connectionFailed("连接已关闭") }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let response = String(data: data, encoding: .utf8) {
                    // SMTP responses end with CRLF, and multi-line responses have "-" after code
                    let lines = response.components(separatedBy: "\r\n")
                    for line in lines {
                        if line.count >= 3 {
                            let code = line.prefix(3)
                            if code.allSatisfy({ $0.isNumber }) {
                                // Check if this is the last line (no "-" after code)
                                if line.count == 3 || (line.count > 3 && line[line.index(line.startIndex, offsetBy: 3)] != "-") {
                                    return response.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                        }
                    }
                }
            } else if count < 0 {
                throw SMTPError.connectionFailed(inputStream.streamError?.localizedDescription ?? "读取失败")
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw SMTPError.connectionFailed("SMTP 响应超时")
    }
}
