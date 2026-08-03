import Foundation
import ConnorGraphCore

struct AssistantBootstrapQueryPlanner: Sendable {
    var maximumTerms: Int = 8
    var maximumQueryCharacters: Int = 240

    func query(for request: AgentChatRequest) -> String {
        let currentText = normalized(request.userMessage)
        let currentTerms = extractedTerms(from: currentText)
        let continuityTerms = request.recentMessages.suffix(6).reversed().flatMap { message -> [String] in
            let messageTerms = extractedTerms(from: normalized(message.content))
            let continuesCurrentTopic = messageTerms.contains {
                isRelevantContinuityTerm($0, currentText: currentText, currentTerms: currentTerms)
            }
            return continuesCurrentTopic ? messageTerms : []
        }

        var terms = deduplicated(currentTerms + continuityTerms)
        if terms.isEmpty {
            terms = fallbackTerms(from: currentText)
        }

        var selected: [String] = []
        for term in terms where selected.count < maximumTerms {
            let candidate = (selected + [term]).joined(separator: ";")
            guard candidate.count <= maximumQueryCharacters else { continue }
            selected.append(term)
        }
        return selected.joined(separator: ";")
    }

    private func extractedTerms(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return deduplicated(
            markedPhrases(in: text)
                + domainTerms(in: text)
                + technicalTerms(in: text)
        )
    }

    private func markedPhrases(in text: String) -> [String] {
        let pairs: [(String, String)] = [
            ("**", "**"), ("`", "`"), ("\"", "\""),
            ("“", "”"), ("‘", "’"), ("《", "》")
        ]
        return pairs.flatMap { opening, closing in
            substrings(in: text, opening: opening, closing: closing)
        }.flatMap(splitCompositeTerm)
    }

    private func substrings(in text: String, opening: String, closing: String) -> [String] {
        var output: [String] = []
        var cursor = text.startIndex
        while let openRange = text.range(of: opening, range: cursor..<text.endIndex),
              let closeRange = text.range(of: closing, range: openRange.upperBound..<text.endIndex) {
            let value = String(text[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isUseful(value) { output.append(value) }
            cursor = closeRange.upperBound
        }
        return output
    }

    private func splitCompositeTerm(_ value: String) -> [String] {
        var terms = [value]
        for pair in [("（", "）"), ("(", ")")] {
            terms.append(contentsOf: substrings(in: value, opening: pair.0, closing: pair.1))
        }
        let outer = value
            .replacingOccurrences(of: #"（[^）]+）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^\)]+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if isUseful(outer) { terms.append(outer) }
        return terms
    }

    private func domainTerms(in text: String) -> [String] {
        let suffixes = [
            "基金", "系统", "项目", "产品", "平台", "公司", "机构", "计划",
            "功能", "工具", "会话", "记录", "笔记", "邮件", "网站", "网页", "同学"
        ]
        let segments = text.components(separatedBy: retrievalSeparators).filter { !$0.isEmpty }
        var output: [String] = []
        for segment in segments {
            for suffix in suffixes {
                var searchStart = segment.startIndex
                while let range = segment.range(of: suffix, range: searchStart..<segment.endIndex) {
                    let prefix = String(segment[..<range.upperBound])
                    let afterPossessive = prefix.split(separator: "的", omittingEmptySubsequences: true).last.map(String.init) ?? prefix
                    let bounded = String(afterPossessive.suffix(10))
                    let cleaned = stripRequestPrefix(from: bounded)
                    if isUseful(cleaned) { output.append(cleaned) }
                    searchStart = range.upperBound
                }
            }
        }
        return output
    }

    private func technicalTerms(in text: String) -> [String] {
        let pattern = #"[A-Za-z0-9][A-Za-z0-9._+\-]*(?:[ \t]+[A-Za-z0-9][A-Za-z0-9._+\-]*){0,2}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let recognizedLowercaseTerms: Set<String> = ["ai", "agent", "llm", "rag", "mcp", "memory", "os"]
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let value = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let isDistinctive = value.contains(where: { $0.isUppercase || $0.isNumber })
                || words.contains { recognizedLowercaseTerms.contains($0.lowercased()) }
            return isDistinctive && isUseful(value) ? value : nil
        }
    }

    private func fallbackTerms(from text: String) -> [String] {
        let plan = MemorySearchQueryParser.parse(text)
        return deduplicated(plan.terms.compactMap { raw in
            let cleaned = stripRequestPrefix(from: raw.trimmingCharacters(in: retrievalSeparators))
            guard isUseful(cleaned) else { return nil }
            return cleaned.count <= 32 ? cleaned : String(cleaned.suffix(32))
        })
    }

    private func isRelevantContinuityTerm(
        _ candidate: String,
        currentText: String,
        currentTerms: [String]
    ) -> Bool {
        if currentTerms.contains(where: { overlaps($0, candidate) }) { return true }
        if currentText.localizedCaseInsensitiveContains(candidate) { return true }

        let compactCandidate = candidate.filter { !$0.isWhitespace && !$0.isPunctuation }
        guard compactCandidate.count >= 4 else { return false }
        let anchorLength = min(4, max(2, compactCandidate.count / 2))
        return currentText.localizedCaseInsensitiveContains(String(compactCandidate.prefix(anchorLength)))
    }

    private func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let right = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return left == right || (min(left.count, right.count) >= 3 && (left.contains(right) || right.contains(left)))
    }

    private func stripRequestPrefix(from value: String) -> String {
        let prefixes = [
            "为什么", "请你", "请帮我", "帮我", "我想让你", "我想", "我们", "我", "你",
            "查询", "搜索", "查看", "读取", "访问", "打开", "关于", "针对", "给", "以"
        ]
        var result = value.trimmingCharacters(in: retrievalSeparators)
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in prefixes where result.hasPrefix(prefix) && result.count > prefix.count + 1 {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(in: retrievalSeparators)
                didStrip = true
                break
            }
        }
        return result
    }

    private func isUseful(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: retrievalSeparators)
        guard (2...48).contains(trimmed.count) else { return false }
        return trimmed.contains { $0.isLetter || $0.isNumber }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: retrievalSeparators)
            let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            guard isUseful(normalized), seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var retrievalSeparators: CharacterSet {
        CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
    }
}
