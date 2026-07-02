import Foundation
import ConnorGraphCore

/// MIME parser for email bodies. Handles multipart/alternative, base64/quoted-printable encoding,
/// and charset conversion (UTF-8, GB2312/GBK, Big5, ISO-2022-JP, etc.)
public struct MailMIMEParser: Sendable, Equatable {
    public init() {}

    /// Parse a raw email body (after headers) into a plain text string.
    /// Handles multipart/alternative, multipart/mixed, base64/quoted-printable, charset conversion.
    public func parseBody(rawData: Data?, fallbackString: String, charset: String?, transferEncoding: String?, contentType: String?, boundary: String?) -> String {
        guard let rawData, !rawData.isEmpty else { return fallbackString }

        // Step 1: Decode Content-Transfer-Encoding
        let decodedData = decodeTransferEncoding(rawData, encoding: transferEncoding)

        // Step 2: If multipart, extract text/plain part
        if let contentType = contentType?.lowercased(), contentType.contains("multipart/"),
           let boundary = boundary, !boundary.isEmpty {
            let bodyString = String(data: decodedData, encoding: .utf8) ?? String(decoding: decodedData, as: Unicode.UTF8.self)
            return extractPlainText(from: bodyString, boundary: boundary)
        }

        // Step 3: Single part - convert charset
        return decodeCharset(decodedData, charset: charset) ?? fallbackString
    }

    /// Decode Content-Transfer-Encoding (base64, quoted-printable, 7bit, 8bit)
    public func decodeTransferEncoding(_ data: Data, encoding: String?) -> Data {
        let enc = encoding?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch enc {
        case "quoted-printable", "qp":
            return decodeQuotedPrintable(data)
        case "base64":
            return Data(base64Encoded: data) ?? data
        default:
            return data // 7bit, 8bit, binary - no decoding needed
        }
    }

    /// Convert data to string using charset
    public func decodeCharset(_ data: Data, charset: String?) -> String? {
        let charsetLower = charset?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if charsetLower.isEmpty || charsetLower == "utf-8" || charsetLower == "utf8" {
            return String(data: data, encoding: .utf8)
        }
        let cfEncoding: CFStringEncoding
        switch charsetLower {
        case "gb2312", "gbk", "gb18030": cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case "big5": cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        case "iso-2022-jp": cfEncoding = CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
        case "euc-jp": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)
        case "shift_jis", "shift-jis": cfEncoding = CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        case "euc-kr": cfEncoding = CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        case "iso-8859-1", "latin1": cfEncoding = CFStringEncoding(0x0201)
        case "windows-1252", "cp1252": cfEncoding = CFStringEncoding(0x0500)
        case "iso-8859-2", "latin2": cfEncoding = CFStringEncoding(0x0202)
        case "windows-1251", "cp1251": cfEncoding = CFStringEncoding(0x0501)
        case "koi8-r": cfEncoding = CFStringEncoding(0x0A02)
        default:
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    /// Extract text/plain part from multipart body
    public func extractPlainText(from body: String, boundary: String) -> String {
        let delimiter = "--\(boundary)"
        let parts = body.components(separatedBy: delimiter)
        var bestPlain: String?
        var bestHTML: String?

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("--") else { continue }

            // Split headers and body
            let components = trimmed.components(separatedBy: "\r\n\r\n")
            let headerPart = components.first ?? ""
            let bodyPart = components.dropFirst().joined(separator: "\r\n\r\n")

            // Check Content-Type
            let contentType = headerPart.lowercased()
            if contentType.contains("text/plain") {
                // Extract charset from Content-Type
                let charset = extractCharsetFromContentType(headerPart)
                let transferEncoding = extractTransferEncodingFromHeader(headerPart)
                let decodedBody = decodeTransferEncoding(Data(bodyPart.utf8), encoding: transferEncoding)
                if let text = decodeCharset(decodedBody, charset: charset) {
                    bestPlain = text
                }
            } else if contentType.contains("text/html") && bestPlain == nil {
                // Fallback to HTML if no plain text found
                let charset = extractCharsetFromContentType(headerPart)
                let transferEncoding = extractTransferEncodingFromHeader(headerPart)
                let decodedBody = decodeTransferEncoding(Data(bodyPart.utf8), encoding: transferEncoding)
                if let html = decodeCharset(decodedBody, charset: charset) {
                    bestHTML = html
                }
            } else if contentType.contains("multipart/") {
                // Nested multipart - recursively extract
                let nestedBoundary = extractBoundaryFromContentType(headerPart)
                if let nestedBoundary = nestedBoundary {
                    let nestedText = extractPlainText(from: bodyPart, boundary: nestedBoundary)
                    if !nestedText.isEmpty {
                        bestPlain = nestedText
                    }
                }
            }
        }

        if let plain = bestPlain, !plain.isEmpty {
            return plain
        }
        if let html = bestHTML, !html.isEmpty {
            return stripHTML(html)
        }
        return stripHTML(body)
    }

    /// Extract charset from Content-Type header
    private func extractCharsetFromContentType(_ header: String) -> String? {
        guard let charsetRange = header.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let after = header[charsetRange.upperBound...]
        if let startQuote = after.range(of: "\"") {
            let afterQuote = after[startQuote.upperBound...]
            if let endQuote = afterQuote.range(of: "\"") {
                return String(afterQuote[..<endQuote.lowerBound])
            }
        }
        let endChars = CharacterSet(charactersIn: "; \t\r\n")
        var result = ""
        for char in after {
            if char.unicodeScalars.contains(where: { endChars.contains($0) }) { break }
            result.append(char)
        }
        return result.isEmpty ? nil : result
    }

    /// Extract Content-Transfer-Encoding from header
    private func extractTransferEncodingFromHeader(_ header: String) -> String? {
        guard let range = header.range(of: "Content-Transfer-Encoding:", options: .caseInsensitive) else { return nil }
        let after = header[range.upperBound...]
        let endOfLine = after.firstIndex(of: "\n") ?? after.endIndex
        return String(after[..<endOfLine]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract boundary from Content-Type header
    public func extractBoundaryFromContentType(_ header: String) -> String? {
        guard let boundaryRange = header.range(of: "boundary=", options: .caseInsensitive) else { return nil }
        let after = header[boundaryRange.upperBound...]
        if let startQuote = after.range(of: "\"") {
            let afterQuote = after[startQuote.upperBound...]
            if let endQuote = afterQuote.range(of: "\"") {
                return String(afterQuote[..<endQuote.lowerBound])
            }
        }
        let endChars = CharacterSet(charactersIn: "; \t\r\n")
        var result = ""
        for char in after {
            if char.unicodeScalars.contains(where: { endChars.contains($0) }) { break }
            result.append(char)
        }
        return result.isEmpty ? nil : result
    }

    /// Decode quoted-printable data
    private func decodeQuotedPrintable(_ data: Data) -> Data {
        var result = Data()
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x3D { // '='
                if i + 2 < bytes.count {
                    let hi = bytes[i + 1]
                    let lo = bytes[i + 2]
                    if hi == 0x0A || hi == 0x0D {
                        // Soft line break - skip
                        i += 2
                        if hi == 0x0D && i + 1 < bytes.count && bytes[i + 1] == 0x0A { i += 1 }
                    } else if let byte = UInt8(String(format: "%c%c", hi, lo), radix: 16) {
                        result.append(byte)
                        i += 3
                    } else {
                        result.append(bytes[i])
                        i += 1
                    }
                } else {
                    result.append(bytes[i])
                    i += 1
                }
            } else if bytes[i] == 0x5F { // '_' (RFC 2047 Q encoding)
                result.append(0x20) // space
                i += 1
            } else {
                result.append(bytes[i])
                i += 1
            }
        }
        return result
    }

    /// Strip HTML tags from string
    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse a raw email body into a MailMessageDetail (legacy compatibility)
    public func parsePlainMessage(raw: String, messageID: MailMessageID, summary: MailMessageSummary, maxBodyCharacters: Int = 16_000) -> MailMessageDetail {
        let parts = raw.components(separatedBy: "\n\n")
        let bodyText = parts.dropFirst().joined(separator: "\n\n")
        let truncated = bodyText.count > maxBodyCharacters
        let clipped = String(bodyText.prefix(maxBodyCharacters))
        let body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: clipped, byteCount: bodyText.utf8.count, wasTruncated: truncated), redactedPreview: String(clipped.prefix(500)), omittedReason: truncated ? "body-truncated" : nil, bodyHash: String(abs(bodyText.hashValue)))
        return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: messageID.rawValue, rawHeaderHash: String(abs(raw.hashValue))), body: body)
    }
}
