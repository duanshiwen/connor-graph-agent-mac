import Foundation

/// 一条来自 ENML 正文的内嵌媒体引用（对应 `<en-media/>`）。
public struct ENMLMediaReference: Sendable, Equatable {
    /// 资源 MD5（小写十六进制）。
    public let hash: String
    /// 资源的 MIME 类型（`type` 属性，可能为空）。
    public let mimeType: String?
    /// 资源文件名（`filename` 属性，可能为空）。
    public let filename: String?
    /// 图片替代文本（`alt` 属性，可能为空）。
    public let alt: String?

    public init(hash: String, mimeType: String?, filename: String?, alt: String?) {
        self.hash = hash
        self.mimeType = mimeType
        self.filename = filename
        self.alt = alt
    }
}

/// 将印象笔记 ENML 正文转换为 Markdown。
///
/// 覆盖块级元素：div / p / h1-h6 / ul / ol / li（含嵌套）/ table / tr / td / th /
/// blockquote / pre / hr / en-todo / en-media / en-crypt，以及常用行内样式
/// （strong / em / u / strike / code / a / sup / sub 等）。
/// 未知元素按容器递归展开，确保内容不丢失；script / style 等禁止元素会被忽略。
///
/// - Parameters:
///   - enml: 印象笔记导出的 ENML 正文（`<content>` 里的字符串）。
///   - resolveMedia: 媒体解析回调。返回对应的 Markdown 片段（例如图片用
///     `![名字](attachment:hash)`、视频用 `[名字](attachment:hash)`）；返回 nil 时
///     转换器会输出可读占位符，避免内容整段丢失。
public enum ENMLMarkdownConverter {
    public static func convert(
        _ enml: String,
        resolveMedia: @escaping (ENMLMediaReference) -> String? = { _ in nil }
    ) -> String {
        let root = ENMLParser().parse(enml)
        return ENMLRenderer(resolveMedia: resolveMedia).render(root)
    }

    /// 解码 XML/HTML 实体（含 &nbsp;、&#123;、&#x1F600; 等）。
    static func decodeEntities(_ text: String) -> String {
        var result = text
        let htmlEntities: [(String, String)] = [
            ("&nbsp;", "\u{00A0}"), ("&#160;", "\u{00A0}"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"),
            ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&ldquo;", "“"), ("&rdquo;", "”"),
            ("&laquo;", "«"), ("&raquo;", "»"), ("&rsaquo;", "›"), ("&lsaquo;", "‹"),
            ("&middot;", "·"), ("&times;", "×"), ("&divide;", "÷"),
            ("&euro;", "€"), ("&deg;", "°"), ("&bull;", "•"),
            ("&para;", "¶"), ("&sect;", "§"), ("&acute;", "´"), ("&uml;", "¨")
        ]
        for (entity, replacement) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        if let unescaped = CFXMLCreateStringByUnescapingEntities(nil, result as CFString, nil) {
            return unescaped as String
        }
        return result
    }
}

// MARK: - 极简容错 HTML/ENML 解析器

private final class ENMLNode {
    var name: String
    var text: String
    var attributes: [String: String]
    var children: [ENMLNode]

    init(name: String = "", text: String = "", attributes: [String: String] = [:], children: [ENMLNode] = []) {
        self.name = name
        self.text = text
        self.attributes = attributes
        self.children = children
    }
}

private final class ENMLParser {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "en-media", "en-todo", "hr",
        "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    func parse(_ source: String) -> ENMLNode {
        let chars = Array(source)
        let root = ENMLNode(name: "root")
        var stack: [ENMLNode] = [root]
        var text = ""
        var index = 0

        func flushText() {
            let decoded = ENMLMarkdownConverter.decodeEntities(text)
            if !decoded.isEmpty {
                stack[stack.count - 1].children.append(ENMLNode(text: decoded))
            }
            text = ""
        }

        while index < chars.count {
            guard chars[index] == "<" else {
                text.append(chars[index])
                index += 1
                continue
            }
            let remaining = chars[index...]
            if remaining.starts(with: Array("<!--")) {
                if let close = findSubsequence(chars, from: index + 4, pattern: "-->") {
                    index = close + 3
                } else {
                    index = chars.count
                }
                continue
            }
            if remaining.starts(with: Array("<![CDATA[")) {
                if let close = findSubsequence(chars, from: index + 9, pattern: "]]>") {
                    text.append(contentsOf: chars[(index + 9)..<close])
                    index = close + 3
                } else {
                    text.append(contentsOf: chars[index...])
                    index = chars.count
                }
                continue
            }
            if remaining.starts(with: Array("</")) {
                if let end = findNextGreaterThan(chars, from: index + 2) {
                    let rawName = String(chars[(index + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    flushText()
                    closeTag(rawName.lowercased(), stack: &stack)
                    index = end + 1
                } else {
                    index = chars.count
                }
                continue
            }
            if remaining.starts(with: Array("<!")), let end = findNextGreaterThan(chars, from: index + 2) {
                // DOCTYPE / 注释之外的声明，直接跳过
                index = end + 1
                continue
            }
            if let end = findNextGreaterThan(chars, from: index + 1) {
                let raw = String(chars[(index + 1)..<end])
                let isSelfClosing = raw.hasSuffix("/")
                let body = isSelfClosing ? String(raw.dropLast()) : raw
                let (name, attributes) = parseTag(body)
                flushText()
                if !name.isEmpty {
                    let node = ENMLNode(name: name.lowercased(), attributes: attributes)
                    stack[stack.count - 1].children.append(node)
                    if !isSelfClosing && !Self.voidElements.contains(node.name) {
                        stack.append(node)
                    }
                }
                index = end + 1
            } else {
                text.append(chars[index])
                index += 1
            }
        }
        flushText()
        return root
    }

    private func findSubsequence(_ chars: [Character], from start: Int, pattern: String) -> Int? {
        let needle = Array(pattern)
        guard start >= 0, start + needle.count <= chars.count else { return nil }
        var cursor = start
        while cursor + needle.count <= chars.count {
            if Array(chars[cursor..<(cursor + needle.count)]) == needle {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private func findNextGreaterThan(_ chars: [Character], from start: Int) -> Int? {
        guard start >= 0, start < chars.count else { return nil }
        for cursor in start..<chars.count where chars[cursor] == ">" {
            return cursor
        }
        return nil
    }

    private func closeTag(_ name: String, stack: inout [ENMLNode]) {
        guard stack.count > 1 else { return }
        var cursor = stack.count - 1
        while cursor >= 1, stack[cursor].name != name {
            cursor -= 1
        }
        if cursor >= 1 {
            stack.removeSubrange(cursor...)
        }
    }

    private func parseTag(_ body: String) -> (String, [String: String]) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", [:]) }
        let parts = splitRespectingQuotes(trimmed)
        guard let firstName = parts.first else { return ("", [:]) }
        let name = firstName.lowercased()
        var attributes: [String: String] = [:]
        for part in parts.dropFirst() {
            if let equals = part.firstIndex(of: "=") {
                let key = String(part[..<equals]).trimmingCharacters(in: .whitespaces).lowercased()
                var value = String(part[part.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let first = value.first, first == "\"" || first == "'" {
                    value.removeFirst()
                    if value.last == first { value.removeLast() }
                }
                if !key.isEmpty {
                    attributes[key] = ENMLMarkdownConverter.decodeEntities(value)
                }
            } else if !part.isEmpty {
                attributes[part.lowercased()] = (part.lowercased() == "checked") ? "true" : ""
            }
        }
        return (name, attributes)
    }

    private func splitRespectingQuotes(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character.isWhitespace {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

// MARK: - ENML → Markdown 渲染

private final class ENMLRenderer {
    private let resolveMedia: (ENMLMediaReference) -> String?

    init(resolveMedia: @escaping (ENMLMediaReference) -> String?) {
        self.resolveMedia = resolveMedia
    }

    func render(_ root: ENMLNode) -> String {
        renderBlocks(root.children)
    }

    private func renderBlocks(_ nodes: [ENMLNode]) -> String {
        var blocks: [String] = []
        for node in nodes {
            let rendered = renderBlock(node)
            if !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(rendered.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    private func renderBlock(_ node: ENMLNode) -> String {
        switch node.name {
        case "en-note", "root":
            return renderBlocks(node.children)
        case "div", "p", "section", "article", "header", "footer", "main", "aside",
             "figure", "figcaption", "address", "center", "caption", "title":
            return inline(node)
        case "h1": return "# " + inline(node)
        case "h2": return "## " + inline(node)
        case "h3": return "### " + inline(node)
        case "h4": return "#### " + inline(node)
        case "h5": return "##### " + inline(node)
        case "h6": return "###### " + inline(node)
        case "ul": return renderList(node, ordered: false, depth: 0)
        case "ol": return renderList(node, ordered: true, depth: 0)
        case "blockquote": return renderBlockquote(node)
        case "pre": return renderPreformatted(node)
        case "table": return renderTable(node)
        case "hr": return "---"
        case "dl": return renderDefinitionList(node)
        case "dt": return "**" + inline(node).trimmingCharacters(in: .whitespacesAndNewlines) + "**"
        case "dd": return "  " + inline(node).trimmingCharacters(in: .whitespacesAndNewlines)
        case "script", "style", "head", "meta", "link":
            return ""
        case "":
            // 直接位于块级位置的文本节点（如 <en-note>Body</en-note>）
            return node.text
        default:
            // 未知/行内元素出现在块级位置（en-todo、en-media、en-crypt、br、a 等）：
            // 交给行内渲染，保证内容不丢失。
            return renderInline(node)
        }
    }

    private func inline(_ node: ENMLNode) -> String {
        let text = node.children.map(renderInline).joined()
        return normalizeWhitespace(text)
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderInline(_ node: ENMLNode) -> String {
        let children = node.children.map(renderInline).joined()
        switch node.name {
        case "":
            return node.text
        case "b", "strong":
            let value = children.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "" : "**\(value)**"
        case "i", "em", "cite", "dfn", "var":
            let value = children.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "" : "*\(value)*"
        case "strike", "s", "del":
            let value = children.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "" : "~~\(value)~~"
        case "u", "ins", "big", "small", "font", "span", "abbr", "acronym", "q", "bdo":
            return children
        case "code", "tt", "kbd", "samp":
            let value = children.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return "" }
            return "`" + value.replacingOccurrences(of: "`", with: "\\`") + "`"
        case "sup", "sub":
            return children
        case "a":
            return link(node, children)
        case "br":
            return "\n"
        case "en-todo":
            return node.attributes["checked"] == "true" ? "- [x] " : "- [ ] "
        case "en-media":
            return media(node)
        case "en-crypt":
            return encrypted(node)
        case "img":
            return image(node)
        case "hr":
            return "---"
        case "ul":
            return renderList(node, ordered: false, depth: 0)
        case "ol":
            return renderList(node, ordered: true, depth: 0)
        case "table":
            return renderTable(node)
        case "blockquote":
            return renderBlockquote(node)
        case "pre":
            return renderPreformatted(node)
        case "script", "style":
            return ""
        default:
            return children
        }
    }

    // MARK: 列表（含嵌套）

    private func renderList(_ node: ENMLNode, ordered: Bool, depth: Int) -> String {
        let items = node.children.filter { $0.name == "li" }
        guard !items.isEmpty else { return "" }
        var lines: [String] = []
        var orderedIndex = 1
        for item in items {
            var inlineParts: [String] = []
            var nestedLists: [ENMLNode] = []
            for child in item.children {
                if child.name == "ul" || child.name == "ol" {
                    nestedLists.append(child)
                } else {
                    inlineParts.append(renderInline(child))
                }
            }
            let content = normalizeWhitespace(inlineParts.joined())
            let marker = ordered ? "\(orderedIndex). " : "- "
            let indent = String(repeating: "  ", count: depth)
            var line = indent + marker + content
            if !nestedLists.isEmpty {
                let nested = nestedLists
                    .map { renderList($0, ordered: $0.name == "ol", depth: depth + 1) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if !nested.isEmpty {
                    line += "\n" + nested
                }
            }
            lines.append(line)
            orderedIndex += 1
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 表格

    private struct TableRow {
        var cells: [String]
        var isHeader: Bool
        var alignments: [String?]
    }

    private func renderTable(_ node: ENMLNode) -> String {
        var rows: [TableRow] = []
        for child in node.children {
            switch child.name {
            case "tr":
                rows.append(tableRow(child))
            case "thead", "tbody", "tfoot":
                for row in child.children where row.name == "tr" {
                    rows.append(tableRow(row))
                }
            default:
                continue
            }
        }
        guard !rows.isEmpty else { return "" }

        let headerIndex: Int
        if let index = rows.firstIndex(where: { $0.isHeader }) {
            headerIndex = index
        } else {
            headerIndex = 0
        }
        let header = rows[headerIndex]
        let body = rows.suffix(from: headerIndex + 1).map(\.cells)

        var output: [String] = []
        output.append("| " + header.cells.joined(separator: " | ") + " |")
        let separatorCells = header.alignments.map { alignment -> String in
            switch alignment {
            case "center": return ":---:"
            case "right": return "---:"
            case "left": return ":---"
            default: return "---"
            }
        }
        output.append("| " + separatorCells.joined(separator: " | ") + " |")
        for rowCells in body {
            output.append("| " + rowCells.joined(separator: " | ") + " |")
        }
        return output.joined(separator: "\n")
    }

    private func tableRow(_ node: ENMLNode) -> TableRow {
        var cells: [String] = []
        var alignments: [String?] = []
        var isHeader = false
        for child in node.children {
            guard child.name == "td" || child.name == "th" else { continue }
            if child.name == "th" { isHeader = true }
            cells.append(tableCellText(child))
            alignments.append(textAlignment(child))
        }
        return TableRow(cells: cells, isHeader: isHeader, alignments: alignments)
    }

    private func tableCellText(_ node: ENMLNode) -> String {
        let text = node.children.map(renderInline).joined()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textAlignment(_ node: ENMLNode) -> String? {
        guard let style = node.attributes["style"] else { return nil }
        for rule in style.components(separatedBy: ";") {
            let parts = rule.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard parts.count == 2, parts[0] == "text-align" else { continue }
            switch parts[1] {
            case "center": return "center"
            case "right": return "right"
            case "left": return "left"
            default: return nil
            }
        }
        return nil
    }

    // MARK: 引用 / 代码块 / 定义列表

    private func renderBlockquote(_ node: ENMLNode) -> String {
        let inner = renderBlocks(node.children)
        guard !inner.isEmpty else { return "" }
        return inner
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
    }

    private func renderPreformatted(_ node: ENMLNode) -> String {
        let text = rawText(node)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return "" }
        return "```\n" + lines.joined(separator: "\n") + "\n```"
    }

    private func renderDefinitionList(_ node: ENMLNode) -> String {
        var lines: [String] = []
        for child in node.children {
            switch child.name {
            case "dt":
                lines.append("- **" + inline(child).trimmingCharacters(in: .whitespacesAndNewlines) + "**")
            case "dd":
                lines.append("  " + inline(child).trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

    private func rawText(_ node: ENMLNode) -> String {
        var output = ""
        for child in node.children {
            if child.name.isEmpty {
                output += child.text
            } else if child.name == "br" {
                output += "\n"
            } else if child.name != "script" && child.name != "style" {
                output += rawText(child)
            }
        }
        return output
    }

    // MARK: 行内链接 / 媒体 / 加密 / 图片

    private func link(_ node: ENMLNode, _ children: String) -> String {
        guard let href = node.attributes["href"] else { return children }
        let sanitized = sanitizedHref(href)
        let label = children.isEmpty ? href : children
        guard let sanitized else { return label }
        return "[\(label)](\(sanitized))"
    }

    private func sanitizedHref(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isNewline }) else { return nil }
        let lowered = trimmed.lowercased()
        guard !lowered.hasPrefix("javascript:"),
              !lowered.hasPrefix("vbscript:"),
              !lowered.hasPrefix("data:text/html") else { return nil }
        if let schemeEnd = trimmed.range(of: "://") {
            let scheme = trimmed[..<schemeEnd.lowerBound].lowercased()
            guard ["http", "https", "file", "mailto"].contains(scheme) else { return nil }
        }
        return trimmed
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    private func media(_ node: ENMLNode) -> String {
        guard let hash = node.attributes["hash"]?.lowercased(), !hash.isEmpty else {
            return "[媒体附件]"
        }
        let reference = ENMLMediaReference(
            hash: hash,
            mimeType: node.attributes["type"],
            filename: node.attributes["filename"],
            alt: node.attributes["alt"]
        )
        if let rendered = resolveMedia(reference), !rendered.isEmpty {
            return rendered
        }
        return "[媒体附件:\(hash.prefix(8))…]"
    }

    private func encrypted(_ node: ENMLNode) -> String {
        var text = "🔒 加密内容"
        if let hint = node.attributes["hint"], !hint.isEmpty {
            text += "（提示：\(hint)）"
        }
        return "[\(text)]"
    }

    private func image(_ node: ENMLNode) -> String {
        let alt = node.attributes["alt"] ?? node.attributes["title"] ?? "图片"
        if let src = node.attributes["src"], !src.isEmpty {
            return "![\(alt)](\(src))"
        }
        return "![\(alt)]()"
    }
}
