import Foundation

public enum AgentMarkdownTableAlignment: String, Codable, Sendable, Equatable {
    case leading
    case center
    case trailing
}

public struct AgentMarkdownTable: Codable, Sendable, Equatable {
    public var headers: [String]
    public var alignments: [AgentMarkdownTableAlignment]
    public var rows: [[String]]

    public init(headers: [String], alignments: [AgentMarkdownTableAlignment], rows: [[String]]) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
    }
}

public enum AgentMarkdownBlock: Codable, Sendable, Equatable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedItem(String)
    case orderedItem(number: String, text: String)
    case taskItem(isCompleted: Bool, text: String)
    case quote(String)
    case code(language: String?, text: String)
    case table(AgentMarkdownTable)
    case horizontalRule
    case spacer

    public var id: String {
        switch self {
        case .heading(let level, let text): return "heading-\(level)-\(text.hashValue)"
        case .paragraph(let text): return "paragraph-\(text.hashValue)"
        case .unorderedItem(let text): return "unordered-\(text.hashValue)"
        case .orderedItem(let number, let text): return "ordered-\(number)-\(text.hashValue)"
        case .taskItem(let isCompleted, let text): return "task-\(isCompleted)-\(text.hashValue)"
        case .quote(let text): return "quote-\(text.hashValue)"
        case .code(let language, let text): return "code-\(language ?? "")-\(text.hashValue)"
        case .table(let table): return "table-\(table.headers.joined(separator: "|").hashValue)-\(table.rows.count)"
        case .horizontalRule: return "horizontal-rule"
        case .spacer: return "spacer"
        }
    }
}

public struct AgentMarkdownBlockParser: Sendable {
    public init() {}

    public func parse(_ markdown: String) -> [AgentMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var result: [AgentMarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCodeBlock = false
        var index = 0

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        func appendSpacerIfNeeded() {
            if result.last.map({ if case .spacer = $0 { return true }; return false }) != true {
                result.append(.spacer)
            }
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    result.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    codeLanguage = nil
                    isInCodeBlock = false
                } else {
                    flushParagraph()
                    codeLanguage = parseFenceLanguage(trimmed)
                    isInCodeBlock = true
                }
                index += 1
                continue
            }

            if isInCodeBlock {
                codeLines.append(rawLine)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                appendSpacerIfNeeded()
                index += 1
                continue
            }

            if let table = parseTable(startingAt: index, lines: lines) {
                flushParagraph()
                result.append(.table(table.table))
                index = table.nextIndex
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                result.append(.horizontalRule)
            } else if let heading = parseHeading(trimmed) {
                flushParagraph()
                result.append(.heading(level: heading.level, text: heading.text))
            } else if let item = parseTaskItem(trimmed) {
                flushParagraph()
                result.append(.taskItem(isCompleted: item.isCompleted, text: item.text))
            } else if let item = parseUnorderedItem(trimmed) {
                flushParagraph()
                result.append(.unorderedItem(item))
            } else if let item = parseOrderedItem(trimmed) {
                flushParagraph()
                result.append(.orderedItem(number: item.number, text: item.text))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                var quoteIndex = index
                while quoteIndex < lines.count {
                    let candidate = lines[quoteIndex].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    quoteIndex += 1
                }
                if let quote = normalizedQuoteText(quoteLines) {
                    result.append(.quote(quote))
                }
                index = quoteIndex
                continue
            } else {
                paragraph.append(rawLine.trimmingCharacters(in: .whitespaces))
            }
            index += 1
        }

        if isInCodeBlock, !codeLines.isEmpty { result.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"))) }
        flushParagraph()
        while result.first.map({ if case .spacer = $0 { return true }; return false }) == true {
            result.removeFirst()
        }
        while result.last.map({ if case .spacer = $0 { return true }; return false }) == true {
            result.removeLast()
        }
        return result
    }

    private func normalizedQuoteText(_ lines: [String]) -> String? {
        var start = lines.startIndex
        var end = lines.endIndex
        while start < end, lines[start].isEmpty { start += 1 }
        while end > start, lines[lines.index(before: end)].isEmpty { end = lines.index(before: end) }
        guard start < end else { return nil }

        var normalized: [String] = []
        for line in lines[start..<end] {
            if line.isEmpty, normalized.last?.isEmpty == true { continue }
            normalized.append(line)
        }
        return normalized.joined(separator: "\n")
    }

    private func parseFenceLanguage(_ line: String) -> String? {
        let info = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !info.isEmpty else { return nil }
        return info.components(separatedBy: .whitespaces).first
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private func parseTaskItem(_ line: String) -> (isCompleted: Bool, text: String)? {
        for marker in ["- [ ] ", "* [ ] ", "+ [ ] "] where line.hasPrefix(marker) {
            return (false, String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] ", "+ [x] ", "+ [X] "] where line.hasPrefix(marker) {
            return (true, String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func parseUnorderedItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func parseOrderedItem(_ line: String) -> (number: String, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = String(line[..<dot])
        guard !number.isEmpty, number.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.first == " " else { return nil }
        return (number, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        guard let first = compact.first, first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private func parseTable(startingAt index: Int, lines: [String]) -> (table: AgentMarkdownTable, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"), separatorLine.contains("|") else { return nil }

        let headers = splitTableRow(headerLine)
        let separators = splitTableRow(separatorLine)
        guard !headers.isEmpty, headers.count == separators.count else { return nil }
        guard separators.allSatisfy(isTableSeparatorCell) else { return nil }

        var rows: [[String]] = []
        var nextIndex = index + 2
        while nextIndex < lines.count {
            let line = lines[nextIndex].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.contains("|") else { break }
            var cells = splitTableRow(line)
            if cells.isEmpty { break }
            if cells.count < headers.count {
                cells += Array(repeating: "", count: headers.count - cells.count)
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            nextIndex += 1
        }

        return (AgentMarkdownTable(
            headers: headers,
            alignments: separators.map(tableAlignment),
            rows: rows
        ), nextIndex)
    }

    private func splitTableRow(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private func isTableSeparatorCell(_ cell: String) -> Bool {
        let compact = cell.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        let stripped = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" }
    }

    private func tableAlignment(_ cell: String) -> AgentMarkdownTableAlignment {
        let compact = cell.filter { !$0.isWhitespace }
        let starts = compact.hasPrefix(":")
        let ends = compact.hasSuffix(":")
        if starts && ends { return .center }
        if ends { return .trailing }
        return .leading
    }
}
