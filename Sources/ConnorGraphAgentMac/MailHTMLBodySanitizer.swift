import Foundation

struct MailHTMLDisplayPolicy: Equatable, Sendable {
    enum RemoteContentMode: Equatable, Sendable {
        case block
        case allowForMessage
    }

    var remoteContentMode: RemoteContentMode

    init(remoteContentMode: RemoteContentMode = .block) {
        self.remoteContentMode = remoteContentMode
    }
}

struct MailHTMLBodySanitizationResult: Equatable, Sendable {
    var html: String
    var blockedRemoteImageCount: Int
}

struct MailHTMLBodySanitizer: Sendable {
    func prepareHTML(_ html: String, policy: MailHTMLDisplayPolicy = MailHTMLDisplayPolicy()) -> MailHTMLBodySanitizationResult {
        let sanitizedBody = sanitizeRemoteImages(in: removeExecutableContent(from: html), policy: policy)
        return MailHTMLBodySanitizationResult(
            html: wrapIfNeeded(sanitizedBody.html),
            blockedRemoteImageCount: sanitizedBody.blockedRemoteImageCount
        )
    }

    private func removeExecutableContent(from html: String) -> String {
        var output = html
        output = output.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script>"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?is)<iframe\b[^>]*>.*?</iframe>"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\s+on[a-zA-Z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            with: "",
            options: .regularExpression
        )
        return output
    }

    private func sanitizeRemoteImages(in html: String, policy: MailHTMLDisplayPolicy) -> (html: String, blockedRemoteImageCount: Int) {
        guard policy.remoteContentMode == .block else {
            return (normalizeImageQuotes(in: html), 0)
        }

        let pattern = #"<img\b[^>]*\bsrc\s*=\s*([\"'])(.*?)\1[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return (html, 0)
        }

        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        var output = html
        var blocked = 0

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let src = source.substring(with: match.range(at: 2))
            guard isRemoteImageSource(src) else { continue }

            let imageTag = source.substring(with: match.range(at: 0))
            let alt = attributeValue(named: "alt", in: imageTag) ?? "远程图片"
            let placeholder = remoteImagePlaceholder(remoteURL: src, alt: alt)
            if let range = Range(match.range(at: 0), in: output) {
                output.replaceSubrange(range, with: placeholder)
                blocked += 1
            }
        }

        return (normalizeImageQuotes(in: output), blocked)
    }

    private func normalizeImageQuotes(in html: String) -> String {
        html.replacingOccurrences(
            of: #"(<img\b[^>]*\bsrc)=\s*'([^']*)'"#,
            with: #"$1="$2""#,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func isRemoteImageSource(_ src: String) -> Bool {
        let lowercased = src.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    private func attributeValue(named name: String, in tag: String) -> String? {
        let pattern = #"\b\\#(name)\s*=\s*([\"'])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let source = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: source.length)), match.numberOfRanges >= 4 else {
            return nil
        }
        return source.substring(with: match.range(at: 3))
    }

    private func remoteImagePlaceholder(remoteURL: String, alt: String) -> String {
        """
        <span class="connor-mail-remote-image-placeholder" data-connor-remote-src="\(escapeHTML(remoteURL))">
            <span class="connor-mail-remote-image-icon">🖼️</span>
            <span>已阻止远程图片：\(escapeHTML(alt))</span>
        </span>
        """
    }

    private func wrapIfNeeded(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("<!doctype") || trimmed.lowercased().hasPrefix("<html") {
            return injectBaseStyleIfNeeded(trimmed)
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            \(Self.baseStyle)
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    private func injectBaseStyleIfNeeded(_ html: String) -> String {
        guard !html.contains("connor-mail-remote-image-placeholder") || !html.contains("img { max-width: 100%; height: auto; }") else {
            return html
        }
        if let headRange = html.range(of: "</head>", options: [.caseInsensitive]) {
            var output = html
            output.insert(contentsOf: "<style>\n\(Self.baseStyle)\n</style>\n", at: headRange.lowerBound)
            return output
        }
        return """
        <!DOCTYPE html>
        <html>
        <head><style>\(Self.baseStyle)</style></head>
        <body>\(html)</body>
        </html>
        """
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let baseStyle = """
    body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; font-size: 14px; line-height: 1.55; padding: 0; margin: 0; word-wrap: break-word; overflow-wrap: break-word; color: CanvasText; background: transparent; }
    img { max-width: 100%; height: auto; }
    a { color: -webkit-link; }
    table { max-width: 100%; border-collapse: collapse; }
    pre, code { white-space: pre-wrap; word-break: break-word; }
    .connor-mail-remote-image-placeholder { display: inline-flex; align-items: center; gap: 6px; max-width: 100%; margin: 4px 0; padding: 7px 9px; border: 1px dashed rgba(128,128,128,0.55); border-radius: 8px; color: rgba(90,90,90,0.95); background: rgba(128,128,128,0.10); font-size: 12px; }
    .connor-mail-remote-image-icon { opacity: 0.8; }
    """
}
