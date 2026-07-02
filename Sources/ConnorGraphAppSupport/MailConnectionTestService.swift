import Foundation
import ConnorGraphCore

/// Test email account connections before saving
public struct MailConnectionTestService: Sendable {
    public var credentialStore: AppMailCredentialStore

    public init(credentialStore: AppMailCredentialStore = AppMailCredentialStore()) {
        self.credentialStore = credentialStore
    }

    /// Test IMAP and SMTP connections
    public func testConnection(
        email: String,
        credential: String,
        incomingHost: String,
        incomingPort: Int,
        incomingSecurity: MailConnectionSecurity,
        outgoingHost: String,
        outgoingPort: Int,
        outgoingSecurity: MailConnectionSecurity
    ) async throws -> MailConnectionTestResult {
        // Run IMAP and SMTP tests in parallel
        async let imapTest = testIMAP(
            host: incomingHost,
            port: incomingPort,
            security: incomingSecurity,
            username: email,
            password: credential
        )

        async let smtpTest = testSMTP(
            host: outgoingHost,
            port: outgoingPort,
            security: outgoingSecurity,
            username: email,
            password: credential
        )

        let (imapResult, smtpResult) = try await (imapTest, smtpTest)

        return MailConnectionTestResult(
            imapConnect: imapResult.connect,
            imapAuth: imapResult.auth,
            smtpConnect: smtpResult.connect,
            smtpAuth: smtpResult.auth
        )
    }

    /// Test IMAP connection and authentication
    private func testIMAP(
        host: String,
        port: Int,
        security: MailConnectionSecurity,
        username: String,
        password: String
    ) async throws -> (connect: TestStepResult, auth: TestStepResult) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let client = BlockingIMAPTestClient(host: host, port: port, security: security)
                let connectResult = client.testConnect()
                let authResult: TestStepResult
                if connectResult.isSuccess {
                    authResult = client.testAuth(username: username, password: password)
                } else {
                    authResult = .skipped("连接失败，跳过认证测试")
                }
                continuation.resume(returning: (connect: connectResult, auth: authResult))
            }
        }
    }

    /// Test SMTP connection and authentication
    private func testSMTP(
        host: String,
        port: Int,
        security: MailConnectionSecurity,
        username: String,
        password: String
    ) async throws -> (connect: TestStepResult, auth: TestStepResult) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let client = BlockingSMTPTestClient(host: host, port: port, security: security)
                let connectResult = client.testConnect()
                let authResult: TestStepResult
                if connectResult.isSuccess {
                    authResult = client.testAuth(username: username, password: password)
                } else {
                    authResult = .skipped("连接失败，跳过认证测试")
                }
                continuation.resume(returning: (connect: connectResult, auth: authResult))
            }
        }
    }
}

/// Result of connection test
public struct MailConnectionTestResult: Sendable {
    public let imapConnect: TestStepResult
    public let imapAuth: TestStepResult
    public let smtpConnect: TestStepResult
    public let smtpAuth: TestStepResult

    public var isSuccess: Bool {
        imapConnect.isSuccess && imapAuth.isSuccess &&
        smtpConnect.isSuccess && smtpAuth.isSuccess
    }

    public var summary: String {
        var messages: [String] = []
        messages.append("IMAP 连接: \(imapConnect.description)")
        messages.append("IMAP 认证: \(imapAuth.description)")
        messages.append("SMTP 连接: \(smtpConnect.description)")
        messages.append("SMTP 认证: \(smtpAuth.description)")
        return messages.joined(separator: "\n")
    }
}

/// Result of a single test step
public enum TestStepResult: Sendable, CustomStringConvertible {
    case success(String)
    case failure(String, error: Error?)
    case skipped(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .success(let msg): return "✓ \(msg)"
        case .failure(let msg, _): return "✗ \(msg)"
        case .skipped(let msg): return "⊘ \(msg)"
        }
    }
}

/// Blocking IMAP test client
private class BlockingIMAPTestClient {
    let host: String
    let port: Int
    let security: MailConnectionSecurity

    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    init(host: String, port: Int, security: MailConnectionSecurity) {
        self.host = host
        self.port = port
        self.security = security
    }

    func testConnect() -> TestStepResult {
        var inStream: InputStream?
        var outStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inStream, outputStream: &outStream)
        guard let input = inStream, let output = outStream else {
            return .failure("无法创建到 \(host):\(port) 的连接", error: nil)
        }

        if security == .tls {
            let sslSettings: [String: Any] = [
                kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelTLSv1,
                kCFStreamSSLPeerName as String: host,
                kCFStreamSSLValidatesCertificateChain as String: true
            ]
            input.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))
            output.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))
        }

        input.open()
        output.open()

        self.inputStream = input
        self.outputStream = output

        // Read greeting
        guard let greeting = readLine(timeout: 10) else {
            input.close()
            output.close()
            return .failure("连接超时", error: nil)
        }

        guard greeting.contains("* OK") || greeting.contains("* PREAUTH") else {
            input.close()
            output.close()
            return .failure("服务器拒绝连接: \(greeting)", error: nil)
        }

        return .success("已连接到 \(host):\(port)")
    }

    func testAuth(username: String, password: String) -> TestStepResult {
        guard let input = inputStream, let output = outputStream else {
            return .failure("连接未建立", error: nil)
        }

        // Send LOGIN command
        let loginCmd = "A1 LOGIN \"\(username)\" \"\(password)\"\r\n"
        guard write(loginCmd, to: output) else {
            return .failure("发送 LOGIN 命令失败", error: nil)
        }

        guard let response = readLine(timeout: 10) else {
            return .failure("LOGIN 响应超时", error: nil)
        }

        input.close()
        output.close()

        if response.contains("A1 OK") {
            return .success("认证成功")
        } else if response.contains("A1 NO") {
            return .failure("认证失败: 用户名或密码错误", error: nil)
        } else if response.contains("A1 BAD") {
            return .failure("认证失败: 服务器不支持 LOGIN", error: nil)
        } else {
            return .failure("认证失败: \(response)", error: nil)
        }
    }

    private func write(_ string: String, to stream: OutputStream) -> Bool {
        let data = Array(string.utf8)
        let written = data.withUnsafeBufferPointer { ptr in
            stream.write(ptr.baseAddress!, maxLength: data.count)
        }
        return written == data.count
    }

    private func readLine(timeout: TimeInterval) -> String? {
        guard let inputStream else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let str = String(data: data, encoding: .utf8), str.contains("\r\n") {
                    return str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if count < 0 {
                return nil
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return nil
    }
}

/// Blocking SMTP test client
private class BlockingSMTPTestClient {
    let host: String
    let port: Int
    let security: MailConnectionSecurity

    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    init(host: String, port: Int, security: MailConnectionSecurity) {
        self.host = host
        self.port = port
        self.security = security
    }

    func testConnect() -> TestStepResult {
        // SMTP only supports STARTTLS
        guard security == .startTLS else {
            return .failure("SMTP 仅支持 STARTTLS (端口 587)", error: nil)
        }

        var inStream: InputStream?
        var outStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inStream, outputStream: &outStream)
        guard let input = inStream, let output = outStream else {
            return .failure("无法创建到 \(host):\(port) 的连接", error: nil)
        }

        input.open()
        output.open()

        self.inputStream = input
        self.outputStream = output

        // Read greeting
        guard let greeting = readLine(timeout: 10) else {
            input.close()
            output.close()
            return .failure("连接超时", error: nil)
        }

        guard greeting.hasPrefix("220") else {
            input.close()
            output.close()
            return .failure("服务器拒绝连接: \(greeting)", error: nil)
        }

        return .success("已连接到 \(host):\(port)")
    }

    func testAuth(username: String, password: String) -> TestStepResult {
        guard let input = inputStream, let output = outputStream else {
            return .failure("连接未建立", error: nil)
        }

        // EHLO
        guard write("EHLO \(host)\r\n", to: output) else {
            return .failure("发送 EHLO 失败", error: nil)
        }
        _ = readUntilOk(timeout: 10)

        // STARTTLS
        guard write("STARTTLS\r\n", to: output) else {
            return .failure("发送 STARTTLS 失败", error: nil)
        }
        guard let starttlsResponse = readLine(timeout: 10), starttlsResponse.hasPrefix("220") else {
            return .failure("STARTTLS 失败", error: nil)
        }

        // Upgrade to TLS
        let sslSettings: [String: Any] = [
            kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelTLSv1,
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        input.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))
        output.setProperty(sslSettings, forKey: .init(kCFStreamPropertySSLSettings as String))

        // Re-EHLO
        guard write("EHLO \(host)\r\n", to: output) else {
            return .failure("发送 EHLO 失败", error: nil)
        }
        _ = readUntilOk(timeout: 10)

        // AUTH LOGIN
        guard write("AUTH LOGIN\r\n", to: output) else {
            return .failure("发送 AUTH LOGIN 失败", error: nil)
        }
        guard let authResponse = readLine(timeout: 10), authResponse.hasPrefix("334") else {
            return .failure("AUTH LOGIN 失败", error: nil)
        }

        // Send username
        let usernameB64 = Data(username.utf8).base64EncodedString()
        guard write("\(usernameB64)\r\n", to: output) else {
            return .failure("发送用户名失败", error: nil)
        }
        guard let userResponse = readLine(timeout: 10), userResponse.hasPrefix("334") else {
            return .failure("用户名验证失败", error: nil)
        }

        // Send password
        let passwordB64 = Data(password.utf8).base64EncodedString()
        guard write("\(passwordB64)\r\n", to: output) else {
            return .failure("发送密码失败", error: nil)
        }
        guard let passResponse = readLine(timeout: 10) else {
            return .failure("密码验证超时", error: nil)
        }

        input.close()
        output.close()

        if passResponse.hasPrefix("235") {
            return .success("认证成功")
        } else {
            return .failure("认证失败: \(passResponse)", error: nil)
        }
    }

    private func write(_ string: String, to stream: OutputStream) -> Bool {
        let data = Array(string.utf8)
        let written = data.withUnsafeBufferPointer { ptr in
            stream.write(ptr.baseAddress!, maxLength: data.count)
        }
        return written == data.count
    }

    private func readLine(timeout: TimeInterval) -> String? {
        guard let inputStream else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let str = String(data: data, encoding: .utf8), str.contains("\r\n") {
                    return str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if count < 0 {
                return nil
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return nil
    }

    private func readUntilOk(timeout: TimeInterval) -> Bool {
        guard let inputStream else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if let str = String(data: data, encoding: .utf8), str.contains("250 ") {
                    return true
                }
            } else if count < 0 {
                return false
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return false
    }
}
