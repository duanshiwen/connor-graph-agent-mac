import Foundation
import ConnorGraphCore

/// MIME parser for email bodies. Handles multipart/alternative, base64/quoted-printable encoding,
/// and charset conversion (UTF-8, GB2312/GBK, Big5, ISO-2022-JP, etc.)
public struct MailMIMEBodyResult: Sendable, Equatable {
    public var plainText: String
    public var htmlText: String?

    public init(plainText: String, htmlText: String? = nil) {
        self.plainText = plainText
        self.htmlText = htmlText
    }
}

public struct MailMIMEParser: Sendable, Equatable {
    public init() {}

    public func parsePlainMessage(raw: String, messageID: MailMessageID, summary: MailMessageSummary, maxBodyCharacters: Int) -> MailMessageDetail {
        let bodyStart: String.Index
        if let range = raw.range(of: "\r\n\r\n") {
            bodyStart = range.upperBound
        } else if let range = raw.range(of: "\n\n") {
            bodyStart = range.upperBound
        } else {
            bodyStart = raw.startIndex
        }
        let body = String(raw[bodyStart...])
        let wasTruncated = maxBodyCharacters >= 0 && body.count > maxBodyCharacters
        let text = wasTruncated ? String(body.prefix(maxBodyCharacters)) : body
        let part = MailBodyPart(mimeType: "text/plain", text: text, byteCount: body.utf8.count, wasTruncated: wasTruncated)
        return MailMessageDetail(
            summary: summary,
            headers: MailMessageHeaders(messageIDHeader: messageID.rawValue),
            body: MailMessageBody(
                plainText: part,
                redactedPreview: String(text.prefix(280)),
                omittedReason: wasTruncated ? "body-truncated" : nil
            )
        )
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

    /// Convert data to string using charset.
    /// When charset is nil/unknown and UTF-8 fails, tries common Asian encodings as fallback.
    public func decodeCharset(_ data: Data, charset: String?) -> String? {
        let charsetLower = charset?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if charsetLower.isEmpty || charsetLower == "utf-8" || charsetLower == "utf8" {
            if let s = String(data: data, encoding: .utf8) { return s }
            let fallbackEncodings: [CFStringEncoding] = [
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue),
                CFStringEncoding(CFStringEncodings.big5.rawValue),
                CFStringEncoding(CFStringEncodings.shiftJIS.rawValue),
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
            ]
            for encoding in fallbackEncodings {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(encoding)
                if let s = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) { return s }
            }
            return nil
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

    /// Parse raw email body and return plain text + HTML.
    /// Works entirely in Data domain — no String round-trip for multipart splitting.
    public func parseBodyWithHTML(rawData: Data?, fallbackString: String, charset: String?, transferEncoding: String?, contentType: String?, boundary: String?) -> MailMIMEBodyResult {
        guard let rawData, !rawData.isEmpty else {
            return MailMIMEBodyResult(plainText: fallbackString)
        }

        // Step 1: Decode Content-Transfer-Encoding
        let decodedData = decodeTransferEncoding(rawData, encoding: transferEncoding)

        // Step 2: If multipart (has boundary), extract parts
        if let boundary, !boundary.isEmpty {
            return extractBodyComponents(data: decodedData, boundary: boundary, fallback: fallbackString)
        }

        // Step 3: Single part — charset convert
        let decodedString = decodeCharset(decodedData, charset: charset) ?? fallbackString
        let trimmed = decodedString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<html") || trimmed.hasPrefix("<!doctype") {
            return MailMIMEBodyResult(plainText: stripHTML(decodedString), htmlText: decodedString)
        }
        return MailMIMEBodyResult(plainText: decodedString)
    }

    /// Multipart MIME parser — works in Data domain.
    /// Splits by boundary bytes, parses headers per-part, decodes transfer+charset per-part.
    private func extractBodyComponents(data: Data, boundary: String, fallback: String) -> MailMIMEBodyResult {
        let delimiter = Data("--\(boundary)".utf8)
        let delimiterEnd = Data("--\(boundary)--".utf8)
        
        // Find all parts between boundaries
        var parts: [Data] = []
        var searchStart = data.startIndex
        
        while searchStart < data.endIndex {
            guard let partStart = data[searchStart...].range(of: delimiter)?.upperBound else { break }
            
            // Check if this is the terminating boundary (--boundary--)
            if data[searchStart...].range(of: delimiterEnd)?.lowerBound == data[searchStart...].range(of: delimiter)?.lowerBound {
                // This is the end marker
                break
            }
            
            // Find the next boundary to mark this part's end
            let remaining = data[partStart...]
            if let nextBoundary = remaining.range(of: delimiter) {
                let partData = data[partStart..<nextBoundary.lowerBound]
                // Data slices keep the base collection's indices. Normalize each MIME part
                // before later using 0-based subdata(in:) ranges; otherwise a slice whose
                // startIndex is not 0 can trap with EXC_BREAKPOINT during body parsing.
                parts.append(Data(partData))
                searchStart = nextBoundary.lowerBound
            } else {
                // Last part (no trailing boundary)
                // Normalize for the same reason as above.
                parts.append(Data(remaining))
                searchStart = data.endIndex
            }
        }

        var bestPlain: String?
        var bestHTML: String?

        for partData in parts {
            // Split headers from body at first \r\n\r\n or \n\n
            let headerEnd: Int
            if let r = partData.range(of: Data("\r\n\r\n".utf8))?.upperBound {
                headerEnd = r - partData.startIndex
            } else if let r = partData.range(of: Data("\n\n".utf8))?.upperBound {
                headerEnd = r - partData.startIndex
            } else {
                continue
            }
            
            let headerBytes = headerEnd > 0 ? partData.subdata(in: 0..<headerEnd) : Data()
            guard let headerStr = String(data: headerBytes, encoding: .ascii) else { continue }
            let bodySlice = partData.subdata(in: headerEnd..<partData.count)
            
            // Extract Content-Type
            let headerLower = headerStr.lowercased()
            
            if headerLower.contains("text/plain") || headerLower.contains("text/html") {
                let charset = extractCharsetFromContentType(headerStr)
                let transferEncoding = extractTransferEncodingFromHeader(headerStr)
                let decodedBody = decodeTransferEncoding(bodySlice, encoding: transferEncoding)
                
                if headerLower.contains("text/html") {
                    if let html = decodeCharset(decodedBody, charset: charset) {
                        bestHTML = html
                        if bestPlain == nil { bestPlain = stripHTML(html) }
                    }
                } else {
                    if let text = decodeCharset(decodedBody, charset: charset) {
                        bestPlain = text
                    }
                }
            } else if headerLower.contains("multipart/") {
                // Nested multipart — recursive
                let nestedBoundary = extractBoundaryFromContentType(headerStr)
                if let nestedBoundary {
                    let nested = extractBodyComponents(data: bodySlice, boundary: nestedBoundary, fallback: fallback)
                    if bestPlain == nil, !nested.plainText.isEmpty { bestPlain = nested.plainText }
                    if bestHTML == nil, let h = nested.htmlText { bestHTML = h }
                }
            }
        }

        let plain = bestPlain ?? (bestHTML.map { stripHTML($0) }) ?? stripHTML(fallback)
        return MailMIMEBodyResult(plainText: plain, htmlText: bestHTML)
    }

    // MARK: - Helpers

    /// Decode quoted-printable data. NOTE: _ → space is ONLY for RFC 2047 Q-encoding, NOT for QP transfer encoding.
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
            } else {
                result.append(bytes[i])
                i += 1
            }
        }
        return result
    }

    private func extractCharsetFromContentType(_ header: String) -> String? {
        guard let charsetRange = header.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let after = header[charsetRange.upperBound...]
        if let startQuote = after.range(of: "\"") {
            let afterQuote = after[startQuote.upperBound...]
            if let endQuote = afterQuote.range(of: "\"") { return String(afterQuote[..<endQuote.lowerBound]) }
        }
        return after.trimmingCharacters(in: .whitespaces).split { $0 == ";" || $0 == " " || $0 == "\"" }.first.map(String.init)
    }

    private func extractTransferEncodingFromHeader(_ header: String) -> String? {
        guard let range = header.range(of: "Content-Transfer-Encoding:", options: .caseInsensitive) else { return nil }
        let after = header[range.upperBound...]
        let endOfLine = after.firstIndex(of: "\n") ?? after.endIndex
        return String(after[..<endOfLine]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func extractBoundaryFromContentType(_ header: String) -> String? {
        guard let boundaryRange = header.range(of: "boundary=", options: .caseInsensitive) else { return nil }
        let after = header[boundaryRange.upperBound...]
        if let startQuote = after.range(of: "\"") {
            let afterQuote = after[startQuote.upperBound...]
            if let endQuote = afterQuote.range(of: "\"") { return String(afterQuote[..<endQuote.lowerBound]) }
        }
        return after.trimmingCharacters(in: .whitespaces).split { $0 == ";" || $0 == " " || $0 == "\"" }.first.map(String.init)
    }

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
