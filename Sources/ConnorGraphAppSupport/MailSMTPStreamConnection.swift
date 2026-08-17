import Foundation
import ConnorGraphCore

/// NSStream（InputStream/OutputStream）的同步 read 是阻塞调用：SMTP 服务器不响应时
/// 会无限挂起，任何应用层 deadline 轮询都无法生效（这也是历史上"发送邮件卡住、
/// 很久不完成"的根因）。本实现改用 runloop 事件驱动 + continuation + 超时任务：
/// 读由 StreamDelegate 回调驱动，超时后由定时任务在 runloop 线程关闭流并抛错，
/// 保证在限时内失败而不是永久挂起。
public final class MailSMTPStreamConnection: NSObject, @unchecked Sendable, MailSMTPConnection, StreamDelegate {
    private let host: String
    private let port: Int

    private let lock = NSLock()
    private var runLoop: RunLoop?
    private var runLoopThread: Thread?
    private var isStopped = false

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var readContinuation: CheckedContinuation<String, Error>?
    private var readBuffer = Data()
    private var readTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
        super.init()
    }

    public func connect(timeout: TimeInterval) async throws {
        ensureRunLoopStarted()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            connectContinuation = continuation
            lock.unlock()
            performOnRunLoop { [self] in
                var input: InputStream?
                var output: OutputStream?
                Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
                guard let input, let output else {
                    failConnect(MailSMTPClientError.connectionFailed("Unable to create streams for \(host):\(port)"))
                    return
                }
                input.delegate = self
                output.delegate = self
                if let loop = runLoop {
                    input.schedule(in: loop, forMode: .default)
                    output.schedule(in: loop, forMode: .default)
                }
                lock.lock()
                inputStream = input
                outputStream = output
                lock.unlock()
                input.open()
                output.open()
            }
        }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(timeout, 1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failConnect(MailSMTPClientError.connectionFailed("SMTP connect to \(self?.host ?? "?") timed out"))
        }
    }

    public func readResponse(timeout: TimeInterval) async throws -> String {
        ensureRunLoopStarted()
        if let buffered = takeCompleteReadResponseIfAvailable() { return buffered }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            lock.lock()
            readContinuation = continuation
            lock.unlock()
            readTimeoutTask?.cancel()
            readTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 1) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.timeoutRead()
            }
        }
    }

    public func writeLine(_ line: String) async throws {
        ensureRunLoopStarted()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performOnRunLoop { [self] in
                guard let outputStream else {
                    continuation.resume(throwing: MailSMTPClientError.connectionFailed("SMTP output stream is closed"))
                    return
                }
                let bytes = Array("\(line)\r\n".utf8)
                let deadline = Date().addingTimeInterval(30)
                var total = 0
                while total < bytes.count {
                    guard Date() < deadline else {
                        continuation.resume(throwing: MailSMTPClientError.connectionFailed("SMTP write timed out"))
                        return
                    }
                    let written = bytes.withUnsafeBufferPointer { buffer in
                        outputStream.write(buffer.baseAddress!.advanced(by: total), maxLength: bytes.count - total)
                    }
                    if written < 0 {
                        continuation.resume(throwing: MailSMTPClientError.connectionFailed(outputStream.streamError?.localizedDescription ?? "SMTP write failed"))
                        return
                    }
                    if written == 0 {
                        Thread.sleep(forTimeInterval: 0.02)
                    } else {
                        total += written
                    }
                }
                continuation.resume(returning: ())
            }
        }
    }

    public func startTLS(host: String, timeout: TimeInterval) async throws {
        ensureRunLoopStarted()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            performOnRunLoop { [self] in
                guard let inputStream, let outputStream else {
                    continuation.resume(throwing: MailSMTPClientError.connectionFailed("SMTP streams are closed before STARTTLS"))
                    return
                }
                let settings: [String: Any] = [
                    kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL,
                    kCFStreamSSLPeerName as String: host,
                    kCFStreamSSLValidatesCertificateChain as String: true
                ]
                inputStream.setProperty(settings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
                outputStream.setProperty(settings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
                continuation.resume(returning: ())
            }
        }
    }

    public func close() async {
        ensureRunLoopStarted()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            performOnRunLoop { [self] in
                readTimeoutTask?.cancel()
                connectTimeoutTask?.cancel()
                lock.lock()
                inputStream?.delegate = nil
                outputStream?.delegate = nil
                if let loop = runLoop {
                    inputStream?.remove(from: loop, forMode: .default)
                    outputStream?.remove(from: loop, forMode: .default)
                }
                inputStream?.close()
                outputStream?.close()
                inputStream = nil
                outputStream = nil
                isStopped = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    // MARK: - StreamDelegate（均在 runloop 线程回调）

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            if aStream === inputStream {
                connectTimeoutTask?.cancel()
                lock.lock()
                let continuation = connectContinuation
                connectContinuation = nil
                lock.unlock()
                continuation?.resume()
            }
        case .hasBytesAvailable:
            guard aStream === inputStream, let inputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                lock.lock()
                readBuffer.append(buffer, count: count)
                if let response = Self.completeSMTPResponse(readBuffer) {
                    readBuffer.removeAll()
                    let continuation = readContinuation
                    readContinuation = nil
                    lock.unlock()
                    readTimeoutTask?.cancel()
                    continuation?.resume(returning: response.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    lock.unlock()
                }
            } else if count < 0 {
                let message = inputStream.streamError?.localizedDescription ?? "SMTP read failed"
                lock.lock()
                let continuation = readContinuation
                readContinuation = nil
                lock.unlock()
                readTimeoutTask?.cancel()
                continuation?.resume(throwing: MailSMTPClientError.connectionFailed(message))
            }
        case .endEncountered:
            if aStream === inputStream {
                lock.lock()
                let continuation = readContinuation
                readContinuation = nil
                lock.unlock()
                readTimeoutTask?.cancel()
                continuation?.resume(throwing: MailSMTPClientError.connectionFailed("SMTP connection closed"))
            }
        case .errorOccurred:
            let message = aStream.streamError?.localizedDescription ?? "SMTP stream error"
            if aStream === inputStream {
                lock.lock()
                let read = readContinuation
                let connect = connectContinuation
                readContinuation = nil
                connectContinuation = nil
                lock.unlock()
                readTimeoutTask?.cancel()
                connectTimeoutTask?.cancel()
                read?.resume(throwing: MailSMTPClientError.connectionFailed(message))
                connect?.resume(throwing: MailSMTPClientError.connectionFailed(message))
            }
        default:
            break
        }
    }

    // MARK: - runloop 启动与调度

    /// 懒启动专用 runloop 线程（仅首次调用执行）。runloop 持续运行并处理流事件。
    private func ensureRunLoopStarted() {
        lock.lock()
        if runLoop != nil || isStopped {
            lock.unlock()
            return
        }
        lock.unlock()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.runLoop = RunLoop.current
            self.lock.unlock()
            ready.signal()
            while true {
                self.lock.lock()
                let stopped = self.isStopped
                self.lock.unlock()
                if stopped { break }
                RunLoop.current.run(mode: .default, before: Date.distantFuture)
            }
        }
        thread.name = "connor.mail.smtp.runloop"
        thread.qualityOfService = .userInitiated
        lock.lock()
        runLoopThread = thread
        lock.unlock()
        thread.start()
        ready.wait()
    }

    /// 在 runloop 线程执行 block。runloop 由专用线程持有并持续运行，
    /// 通过 CFRunLoopPerformBlock 注入可确保 block 一定会被执行（不会像
    /// 串行队列那样被 runloop 永久占用而排队卡死）。
    private func performOnRunLoop(_ block: @escaping @Sendable () -> Void) {
        lock.lock()
        let loop = runLoop
        lock.unlock()
        guard let loop else { block(); return }
        CFRunLoopPerformBlock(loop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop.getCFRunLoop())
    }

    private func timeoutRead() {
        performOnRunLoop { [self] in
            lock.lock()
            let continuation = readContinuation
            readContinuation = nil
            lock.unlock()
            guard continuation != nil else { return }
            inputStream?.close()
            continuation?.resume(throwing: MailSMTPClientError.connectionFailed("SMTP response timed out"))
        }
    }

    private func failConnect(_ error: MailSMTPClientError) {
        performOnRunLoop { [self] in
            lock.lock()
            let continuation = connectContinuation
            connectContinuation = nil
            lock.unlock()
            guard continuation != nil else { return }
            inputStream?.close()
            outputStream?.close()
            continuation?.resume(throwing: error)
        }
    }

    /// 同步取出缓冲中已完整的响应；无完整响应返回 nil。必须在异步上下文外调用。
    private func takeCompleteReadResponseIfAvailable() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !readBuffer.isEmpty, let response = Self.completeSMTPResponse(readBuffer) else { return nil }
        readBuffer.removeAll()
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func completeSMTPResponse(_ response: Data) -> String? {
        guard let text = String(data: response, encoding: .utf8) else { return nil }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasSuffix("\n") else { return nil }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last, last.count >= 3 else { return nil }
        let code = last.prefix(3)
        guard code.allSatisfy({ $0.isNumber }) else { return nil }
        if last.count == 3 { return text }
        let markerIndex = last.index(last.startIndex, offsetBy: 3)
        return last[markerIndex] != "-" ? text : nil
    }
}
