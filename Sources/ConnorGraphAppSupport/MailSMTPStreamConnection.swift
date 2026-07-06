import Foundation
import ConnorGraphCore

public final class MailSMTPStreamConnection: @unchecked Sendable, MailSMTPConnection {
    private let host: String
    private let port: Int
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let queue = DispatchQueue(label: "connor.mail.smtp.stream", qos: .utility)

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public func connect(timeout: TimeInterval) async throws {
        try await runOnQueue {
            var input: InputStream?
            var output: OutputStream?
            Stream.getStreamsToHost(withName: self.host, port: self.port, inputStream: &input, outputStream: &output)
            guard let input, let output else {
                throw MailSMTPClientError.connectionFailed("Unable to create streams for \(self.host):\(self.port)")
            }
            input.open()
            output.open()
            self.inputStream = input
            self.outputStream = output
        }
    }

    public func readResponse(timeout: TimeInterval) async throws -> String {
        try await runOnQueue {
            guard let inputStream = self.inputStream else {
                throw MailSMTPClientError.connectionFailed("SMTP input stream is closed")
            }
            let deadline = Date().addingTimeInterval(timeout)
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while Date() < deadline {
                let count = inputStream.read(&buffer, maxLength: buffer.count)
                if count > 0 {
                    data.append(buffer, count: count)
                    if let response = String(data: data, encoding: .utf8), Self.isCompleteSMTPResponse(response) {
                        return response.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if count < 0 {
                    throw MailSMTPClientError.connectionFailed(inputStream.streamError?.localizedDescription ?? "SMTP read failed")
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            throw MailSMTPClientError.connectionFailed("SMTP response timed out after \(Int(timeout))s")
        }
    }

    public func writeLine(_ line: String) async throws {
        try await runOnQueue {
            guard let outputStream = self.outputStream else {
                throw MailSMTPClientError.connectionFailed("SMTP output stream is closed")
            }
            let bytes = Array("\(line)\r\n".utf8)
            try bytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                var total = 0
                while total < bytes.count {
                    let written = outputStream.write(base.advanced(by: total), maxLength: bytes.count - total)
                    if written < 0 {
                        throw MailSMTPClientError.connectionFailed(outputStream.streamError?.localizedDescription ?? "SMTP write failed")
                    }
                    if written == 0 {
                        Thread.sleep(forTimeInterval: 0.02)
                    } else {
                        total += written
                    }
                }
            }
        }
    }

    public func startTLS(host: String, timeout: TimeInterval) async throws {
        try await runOnQueue {
            guard let inputStream = self.inputStream, let outputStream = self.outputStream else {
                throw MailSMTPClientError.connectionFailed("SMTP streams are closed before STARTTLS")
            }
            let settings: [String: Any] = [
                kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL,
                kCFStreamSSLPeerName as String: host,
                kCFStreamSSLValidatesCertificateChain as String: true
            ]
            inputStream.setProperty(settings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
            outputStream.setProperty(settings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
        }
    }

    public func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.inputStream?.close()
                self.outputStream?.close()
                self.inputStream = nil
                self.outputStream = nil
                continuation.resume()
            }
        }
    }

    private func runOnQueue<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func isCompleteSMTPResponse(_ response: String) -> Bool {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasSuffix("\n") else { return false }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last, last.count >= 3 else { return false }
        let code = last.prefix(3)
        guard code.allSatisfy({ $0.isNumber }) else { return false }
        if last.count == 3 { return true }
        let markerIndex = last.index(last.startIndex, offsetBy: 3)
        return last[markerIndex] != "-"
    }
}
