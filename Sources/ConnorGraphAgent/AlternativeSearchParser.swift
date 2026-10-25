import Foundation

/// Parses actual result headings, never navigation links or verification-page text.
enum AlternativeSearchParser {
    static func results(from html: String, engine: String) -> [NativeWebSearchResultItem] {
        let html = html.replacingOccurrences(of: #"(?is)<script\b.*?</script>|<style\b.*?</style>"#, with: "", options: .regularExpression)
        let patterns = [
            #"(?is)<h3\b[^>]*>\s*(?:<!--.*?-->\s*)*<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>.*?</h3>"#,
            #"(?is)<a\b[^>]*href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<h3\b[^>]*>(.*?)</h3>"#
        ]
        let nsHTML = html as NSString
        var matches: [NSTextCheckingResult] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            matches += regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        }
        var seen = Set<String>()
        return matches.sorted { $0.range.location < $1.range.location }.compactMap { match in
            let title = text(nsHTML.substring(with: match.range(at: 2)))
            guard !title.isEmpty, let url = resultURL(nsHTML.substring(with: match.range(at: 1)), engine: engine), seen.insert(url).inserted else { return nil }
            let start = NSMaxRange(match.range)
            let tail = nsHTML.substring(with: NSRange(location: start, length: min(3000, nsHTML.length - start)))
            let snippetPattern = #"(?is)<(?:p|div|a)\b[^>]*(?:class|id)=["'][^"']*(?:summary|fz-mid|res-desc|res-con)[^"']*["'][^>]*>(.*?)</(?:p|div|a)>"#
            let snippetMatch = try? NSRegularExpression(pattern: snippetPattern).firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length))
            let snippet = snippetMatch.map { text((tail as NSString).substring(with: $0.range(at: 1))) } ?? ""
            return NativeWebSearchResultItem(title: title, url: url, snippet: String(snippet.prefix(500)))
        }
    }

    private static func resultURL(_ href: String, engine: String) -> String? {
        let base = URL(string: engine == "so360" ? "https://m.so.com" : "https://www.sogou.com")!
        guard var url = URL(string: entities(href), relativeTo: base)?.absoluteURL else { return nil }
        if engine == "so360", url.host == "m.so.com", url.path == "/jump",
           let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value {
            guard let destination = URL(string: target) else { return nil }
            url = destination
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url.absoluteString
    }

    private static func text(_ value: String) -> String {
        entities(value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entities(_ value: String) -> String {
        var value = value
        let regex = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in regex.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let raw = (value as NSString).substring(with: match.range(at: 1))
            let code = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let code, let scalar = UnicodeScalar(code), let range = Range(match.range, in: value) {
                value.replaceSubrange(range, with: String(scalar))
            }
        }
        for (from, to) in [("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value
    }
}
