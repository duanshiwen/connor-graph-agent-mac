import Foundation

/// 不可信笔记 HTML 的净化器：移除脚本/样式块与危险标签，并剥掉事件属性与危险协议。
///
/// 策略：允许 Notion 导出常用的可见块级/行内标签（标题、段落、列表、表格、引用、
/// 代码块、图片、链接等），保留其 inline style（Notion 排版大量依赖内联样式），
/// 但彻底移除可执行或可外联的标签，避免渲染 WebView 时执行不可信内容。
public enum NoteHTMLSanitizer {
    /// 需要整体删除的块（标签内可能带属性）。
    private static let strippedBlocks: [(pattern: String, replacement: String)] = [
        // 配对标签同时覆盖“未闭合”形式：`<script>...` 没有 `</script>`
        // 时也会被剥掉，避免把后续正文吞进脚本/嵌入内容。
        ("(?is)<script\\b[^>]*>(?:.*?</script>)?", ""),
        ("(?is)<style\\b[^>]*>(?:.*?</style>)?", ""),
        ("(?is)<iframe\\b[^>]*>(?:.*?</iframe>)?", ""),
        ("(?is)<object\\b[^>]*>(?:.*?</object>)?", ""),
        ("(?is)<embed\\b[^>]*>(?:.*?</embed>)?", ""),
        ("(?is)<applet\\b[^>]*>(?:.*?</applet>)?", ""),
        ("(?is)<link\\b[^>]*>", ""),
        ("(?is)<meta\\b[^>]*>", ""),
        ("(?is)<base\\b[^>]*>", ""),
        ("(?is)<template\\b[^>]*>(?:.*?</template>)?", ""),
        ("(?is)<noscript\\b[^>]*>(?:.*?</noscript>)?", ""),
        ("(?is)<form\\b[^>]*>(?:.*?</form>)?", ""),
        ("(?is)<input\\b[^>]*>", ""),
        ("(?is)<button\\b[^>]*>(?:.*?</button>)?", ""),
        ("(?is)<select\\b[^>]*>(?:.*?</select>)?", ""),
        ("(?is)<textarea\\b[^>]*>(?:.*?</textarea>)?", ""),
        ("(?is)<svg\\b[^>]*>(?:.*?</svg>)?", ""),
        ("(?is)<math\\b[^>]*>(?:.*?</math>)?", ""),
        ("(?is)<head\\b[^>]*>(?:.*?</head>)?", ""),
        ("(?is)<!doctype\\b[^>]*>", ""),
        ("(?is)<\\?xml[^>]*\\?>", ""),
    ]

    /// 净化一段 Notion HTML 片段，返回可直接嵌入 `<body>` 的 HTML。
    public static func sanitize(_ html: String) -> String {
        var value = html
        for block in strippedBlocks {
            value = value.replacingOccurrences(of: block.pattern, with: block.replacement, options: .regularExpression)
        }
        // 移除所有事件属性（onclick、onerror 等），支持单引号/双引号/无引号三种写法。
        value = value.replacingOccurrences(
            of: #"(?is)\s+on[a-z][a-z0-9_]*\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            with: "",
            options: .regularExpression
        )
        // 危险协议：href/src 上的 javascript:、vbscript:、data:（除 data:image 内联图）。
        value = value.replacingOccurrences(
            of: #"(?is)(href|src)\s*=\s*["']\s*(?:javascript|vbscript|data:(?!image/))[^"']*["']"#,
            with: "$1=\"\"",
            options: .regularExpression
        )
        return value
    }

    /// 组装成可在只读 WebView 中安全渲染的完整 HTML 文档。
    public static func document(html: String) -> String {
        let sanitized = sanitize(html)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>\(sanitized)</body>
        </html>
        """
    }
}
