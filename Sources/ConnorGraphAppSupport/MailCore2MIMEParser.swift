import Foundation
import ConnorGraphCore

#if canImport(MailCore)
import MailCore
#endif

public struct MailCore2MIMEParser: Sendable, Equatable {
    private let fallbackParser: MailMIMEParser

    public init(fallbackParser: MailMIMEParser = MailMIMEParser()) {
        self.fallbackParser = fallbackParser
    }

    public func parseFullMessageBody(rawData: Data?, fallbackString: String) throws -> MailMIMEBodyResult {
        guard let rawData, !rawData.isEmpty else {
            return MailMIMEBodyResult(plainText: fallbackString)
        }

        #if canImport(MailCore)
        return parseMessageBody(rawData: rawData, parser: MCOMessageParser(data: rawData), fallbackString: fallbackString)
        #else
        return fallbackParser.parseFullMessageBody(rawData: rawData, fallbackString: fallbackString)
        #endif
    }

    #if canImport(MailCore)
    func parseMessageBody(rawData: Data, parser: MCOMessageParser?, fallbackString: String) -> MailMIMEBodyResult {
        let plain = (parser?.plainTextBodyRenderingAndStripWhitespace(false) ?? parser?.plainTextBodyRendering() ?? parser?.plainTextRendering() ?? fallbackString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let html = (parser?.htmlRendering(with: nil) ?? parser?.htmlBodyRendering())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRawHeader = String(data: rawData.prefix(4096), encoding: .ascii)?.lowercased() ?? ""
        let hasPlainAlternative = normalizedRawHeader.contains("multipart/alternative") && normalizedRawHeader.contains("text/plain")
        let fallback = hasPlainAlternative || plain.isEmpty || html?.isEmpty != false
            ? fallbackParser.parseFullMessageBody(rawData: rawData, fallbackString: fallbackString)
            : MailMIMEBodyResult(plainText: plain, htmlText: html)
        let preferredPlain = hasPlainAlternative && !fallback.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            : plain

        if !preferredPlain.isEmpty {
            return MailMIMEBodyResult(plainText: preferredPlain, htmlText: html?.isEmpty == false ? html : fallback.htmlText)
        }
        if let html, !html.isEmpty {
            return MailMIMEBodyResult(plainText: fallback.plainText, htmlText: html)
        }
        return fallbackParser.parseFullMessageBody(rawData: rawData, fallbackString: fallbackString)
    }
    #endif
}
