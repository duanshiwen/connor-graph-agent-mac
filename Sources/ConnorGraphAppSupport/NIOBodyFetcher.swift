import Foundation
import ConnorGraphCore

/// Compatibility wrapper for parsing raw IMAP MIME messages without adding SwiftNIO as a package dependency.
///
/// The old implementation opened a one-shot NIO/NIOSSL/NIOIMAP connection here, but the
/// current package no longer declares those modules. Commercial sync should fetch raw
/// message bytes through `MailIMAPAdapter` / `MailProtocolAdapter`; this type keeps the
/// robust raw MIME `parseMessage` path used by `MailIMAPInitialSyncService` and tests.
public final class NIOBodyFetcher: @unchecked Sendable {
    private let host: String
    private let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public func fetchRawMessage(usernames: [String], password: String, uid: String) async throws -> Data? {
        _ = (host, port, usernames, password, uid)
        return nil
    }

    public static func parseMessage(
        rawMIME data: Data, uid: String,
        accountID: MailAccountID, mailboxID: MailMailboxID,
        fallbackRecipient: MailAddress, snippet: String
    ) -> MailMessageDetail? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }
        let headerStr = String(data: data[..<headerEnd], encoding: .ascii)
            ?? String(decoding: data[..<headerEnd], as: Unicode.UTF8.self)
        let bodyData = data[headerEnd...]

        let unfolded = headerStr.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
        let subject = decodeRFC2047(headerValue(in: unfolded, for: "Subject")) ?? "（无主题）"
        let fromAddr = parseAddr(headerValue(in: unfolded, for: "From")) ?? MailAddress(email: "unknown@example.com")
        let toAddrs = parseAddrList(headerValue(in: unfolded, for: "To"))
        let ccAddrs = parseAddrList(headerValue(in: unfolded, for: "Cc"))
        let date = parseDate(headerValue(in: unfolded, for: "Date"))
        let msgID = headerValue(in: unfolded, for: "Message-ID")
        let ct = headerValue(in: unfolded, for: "Content-Type") ?? ""
        let cte = headerValue(in: unfolded, for: "Content-Transfer-Encoding") ?? ""

        let parser = MailMIMEParser()
        let bodyResult = parser.parseBodyWithHTML(
            rawData: Data(bodyData), fallbackString: snippet,
            charset: extractCharset(from: ct),
            transferEncoding: cte.isEmpty ? nil : cte,
            contentType: ct, boundary: extractBoundary(from: ct)
        )

        let clean = stripHTML(bodyResult.plainText)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = String(clean.prefix(300))

        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-\(uid)"),
            accountID: accountID, mailboxID: mailboxID,
            threadID: msgID.flatMap { MailThreadID(rawValue: $0.trimmingCharacters(in: CharacterSet.whitespaces)) },
            subject: subject, from: fromAddr,
            to: toAddrs.isEmpty ? [fallbackRecipient] : toAddrs,
            cc: ccAddrs,
            date: date ?? Date(),
            snippet: preview.isEmpty ? "（无正文摘要）" : preview,
            flags: MailMessageFlags(),
            hasAttachments: ct.localizedCaseInsensitiveContains("multipart/mixed")
        )
        let body = MailMessageBody(
            plainText: MailBodyPart(mimeType: "text/plain", text: bodyResult.plainText, byteCount: bodyResult.plainText.utf8.count),
            htmlText: bodyResult.htmlText.map { MailBodyPart(mimeType: "text/html", text: $0, byteCount: $0.utf8.count) },
            redactedPreview: String(bodyResult.plainText.prefix(500)),
            bodyHash: String(abs(bodyResult.plainText.hashValue))
        )
        return MailMessageDetail(summary: summary,
            headers: MailMessageHeaders(messageIDHeader: msgID ?? "", rawHeaderHash: String(abs(headerStr.hashValue))),
            body: body)
    }

    // MARK: - Static helpers

    static func headerValue(in headers: String, for name: String) -> String? {
        let target = name.lowercased() + ":"
        for line in headers.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix(target) else { continue }
            return String(trimmed.dropFirst(target.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func findHeaderEnd(in data: Data) -> Data.Index? {
        if let r = data.range(of: Data("\r\n\r\n".utf8))?.upperBound { return r }
        if let r = data.range(of: Data("\n\n".utf8))?.upperBound { return r }
        return nil
    }

    static func extractCharset(from ct: String) -> String? {
        guard let r = ct.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let after = ct[r.upperBound...]
        if let sq = after.range(of: "\""), let eq = after[sq.upperBound...].range(of: "\"") { return String(after[sq.upperBound..<eq.lowerBound]) }
        return after.trimmingCharacters(in: .whitespaces).split { $0 == ";" || $0 == " " || $0 == "\"" }.first.map(String.init)
    }

    static func extractBoundary(from ct: String) -> String? {
        guard let r = ct.range(of: "boundary=", options: .caseInsensitive) else { return nil }
        let after = ct[r.upperBound...]
        if let sq = after.range(of: "\""), let eq = after[sq.upperBound...].range(of: "\"") { return String(after[sq.upperBound..<eq.lowerBound]) }
        return after.trimmingCharacters(in: .whitespaces).split { $0 == ";" || $0 == " " || $0 == "\"" }.first.map(String.init)
    }

    static func parseDate(_ v: String?) -> Date? {
        guard let v else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: v.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
        }
        return nil
    }

    static func parseAddr(_ v: String?) -> MailAddress? {
        guard let v = v?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if let s = v.range(of: "<"), let e = v.range(of: ">", range: s.upperBound..<v.endIndex) {
            let n = String(v[..<s.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            return MailAddress(name: n.isEmpty ? nil : n, email: String(v[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespaces))
        }
        return MailAddress(email: v.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
    }

    static func parseAddrList(_ v: String?) -> [MailAddress] {
        guard let v else { return [] }
        return v.split(separator: ",").compactMap { parseAddr(String($0)) }
    }

    static func decodeRFC2047(_ s: String?) -> String? {
        guard let s else { return nil }
        let pattern = #"=\?([^?]+)\?([QBqb])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var last = 0
        for m in matches {
            let mr = m.range
            if mr.location > last {
                let gap = ns.substring(with: NSRange(location: last, length: mr.location - last))
                if !gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result += gap }
            }
            guard let cr = Range(m.range(at: 1), in: s), let er = Range(m.range(at: 2), in: s), let tr = Range(m.range(at: 3), in: s) else {
                result += ns.substring(with: mr); last = mr.location + mr.length; continue
            }
            let charset = String(s[cr]).lowercased()
            let enc = String(s[er]).uppercased()
            let txt = String(s[tr])
            if let decoded = decodeOne(charset: charset, encoding: enc, text: txt) { result += decoded }
            else { result += ns.substring(with: mr) }
            last = mr.location + mr.length
        }
        if last < ns.length { result += ns.substring(from: last) }
        return result
    }

    static func decodeOne(charset: String, encoding: String, text: String) -> String? {
        if encoding == "B" { return decodeData(Data(base64Encoded: text), charset: charset) }
        if encoding == "Q" {
            var bytes = [UInt8]()
            var i = text.startIndex
            while i < text.endIndex {
                if text[i] == "=", i < text.index(text.endIndex, offsetBy: -2), let b = UInt8(text[text.index(after: i)...text.index(i, offsetBy: 2)], radix: 16) {
                    bytes.append(b); i = text.index(i, offsetBy: 3)
                } else if text[i] == "_" { bytes.append(0x20); i = text.index(after: i) }
                else { if let v = text[i].asciiValue { bytes.append(v) }; i = text.index(after: i) }
            }
            return decodeData(Data(bytes), charset: charset)
        }
        return nil
    }

    static func decodeData(_ data: Data?, charset: String) -> String? {
        guard let data else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        let cf: CFStringEncoding
        switch charset {
        case "gb2312", "gbk", "gb18030": cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case "big5": cf = CFStringEncoding(CFStringEncodings.big5.rawValue)
        case "iso-2022-jp": cf = CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
        default: return String(data: data, encoding: .ascii)
        }
        return String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
    }

    static func stripHTML(_ t: String) -> String {
        t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

