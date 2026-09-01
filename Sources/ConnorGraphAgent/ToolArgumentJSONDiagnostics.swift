import Foundation

/// 工具参数 JSON 的轻量诊断层。
///
/// 目标：把「笼统的 schema 重发提示」升级为「具体原因 + 长度 + 位置 + 是否疑似截断」，
/// 并在超长/截断场景给出明确的行动指引（勿用批量通道调写入工具、改为直接调用、拆小）。
///
/// 设计约束（红线）：
/// - 客户端任何地方都不按长度裁剪参数原文；截断只可能来自上游流式提前停流。
/// - 本层只做诊断与报错，不改变任何工具接口或参数结构。
public enum ToolArgumentJSONDiagnostics {
    /// 诊断载荷：错误信息 + 元数据。可直接序列化为 INVALID_JSON 标记，也可从标记解包。
    public struct JSONErrorPayload: Equatable, Sendable {
        public var raw: String
        public var length: Int
        public var truncated: Bool
        public var summary: String
        public var offset: Int?
        public var line: Int?
        public var column: Int?

        public init(
            raw: String,
            length: Int,
            truncated: Bool,
            summary: String,
            offset: Int? = nil,
            line: Int? = nil,
            column: Int? = nil
        ) {
            self.raw = raw
            self.length = length
            self.truncated = truncated
            self.summary = summary
            self.offset = offset
            self.line = line
            self.column = column
        }
    }

    /// 疑似「因输入过长被截断」的长度下界（字符数）：低于此值更像普通语法错误。
    public static let likelyTruncatedMinimumLength = 256
    /// 批量通道写入预检的软上限（字符数）：超过即建议改用直接调用。
    public static let toolArgumentsSoftLimit = 8_192
    /// 不应通过批量通道调用的写入工具名（匹配时忽略大小写）。
    public static let writeToolNames: Set<String> = [
        "ApplyPatch", "editWorkspaceFile", "writeFile", "appendFile", "createFile",
        "deleteWorkspaceFile", "moveFile", "copyFile"
    ]

    // MARK: - 入口

    /// 分析一段参数 JSON。
    /// - 合法 JSON 对象 → 返回 nil（无需报错）。
    /// - 非法 / 非对象 → 返回诊断载荷。
    public static func analyze(_ json: String) -> JSONErrorPayload? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return JSONErrorPayload(raw: json, length: json.count, truncated: false, summary: "arguments 为空")
        }
        let data = Data(trimmed.utf8)
        if (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil {
            return nil
        }
        if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return JSONErrorPayload(
                raw: json,
                length: json.count,
                truncated: false,
                summary: "解析成功但不是 JSON 对象（顶层应为 {\"key\": ...} 对象）"
            )
        }
        // 语法非法 → 扫描定位与分类。
        let scan = scan(trimmed)
        let truncated = scan.isUnclosed && json.count >= likelyTruncatedMinimumLength
        let (offset, summary) = summarize(scan, truncated: truncated)
        let position = offset.flatMap { lineColumn(of: $0, in: trimmed) }
        return JSONErrorPayload(
            raw: json,
            length: json.count,
            truncated: truncated,
            summary: summary,
            offset: offset,
            line: position?.line,
            column: position?.column
        )
    }

    /// 生成 INVALID_JSON 流式标记（带诊断元数据）。原文完整保留，绝不裁剪。
    public static func invalidJSONMarker(payload: JSONErrorPayload) -> String {
        var parts: [String] = []
        parts.append("\"INVALID_JSON\":\(escapedJSONString(payload.raw))")
        parts.append("\"__length\":\(payload.length)")
        parts.append("\"__truncated\":\(payload.truncated)")
        parts.append("\"__json_error\":\(escapedJSONString(payload.summary))")
        if let offset = payload.offset { parts.append("\"__offset\":\(offset)") }
        if let line = payload.line { parts.append("\"__line\":\(line)") }
        if let column = payload.column { parts.append("\"__column\":\(column)") }
        return "{\(parts.joined(separator: ","))}"
    }

    /// 若给定 JSON 是 INVALID_JSON 标记，解包出其中的诊断载荷；否则返回 nil。
    public static func unwrapInvalidJSONMarker(_ json: String) -> JSONErrorPayload? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["INVALID_JSON"] as? String else { return nil }
        return JSONErrorPayload(
            raw: raw,
            length: object["__length"] as? Int ?? raw.count,
            truncated: object["__truncated"] as? Bool ?? false,
            summary: object["__json_error"] as? String ?? "invalid JSON",
            offset: object["__offset"] as? Int,
            line: object["__line"] as? Int,
            column: object["__column"] as? Int
        )
    }

    // MARK: - 统一错误模板 / 行动指引

    public static func isWriteToolName(_ name: String) -> Bool {
        writeToolNames.contains { $0.lowercased() == name.lowercased() }
    }

    public static var writeToolGuidance: String {
        "请勿使用批量通道（parallel_tool_query / parallel_tool_execute）调用 ApplyPatch 等写入工具——请改为直接调用 ApplyPatch；若内容仍过长，拆成 create + 多次 edit/append 分段写入。"
    }

    public static func errorDescription(forToolName toolName: String, payload: JSONErrorPayload) -> String {
        let guidance = isWriteToolName(toolName)
            ? writeToolGuidance
            : "请修正参数后重试；超长内容请拆分，避免流式输出把 JSON 截断。"
        if payload.truncated {
            return "工具调用参数可能在流式传输中被截断（共收到 \(payload.length) 字符，JSON 未闭合，疑似因输入过长）。\(guidance)"
        }
        let position = payload.line.map { "（偏移 \(payload.offset ?? 0)，第 \($0) 行第 \(payload.column ?? 0) 列）" } ?? ""
        return "工具调用 arguments 不是合法 JSON：\(payload.summary)\(position)（长度 \(payload.length)）。\(guidance)"
    }

    // MARK: - 批量写入预检

    /// 单条子调用的写入预检：写工具 + 参数超长 → 返回拦截文案；否则 nil。
    public static func batchWritePreflightIssue(toolName: String, argumentsJSON: String, index: Int) -> String? {
        guard isWriteToolName(toolName) else { return nil }
        let length = argumentsJSON.count
        guard length > toolArgumentsSoftLimit else { return nil }
        return "calls[\(index)] 使用批量通道调用写入工具 \(toolName)，参数过长（\(length) 字符 > 软上限 \(toolArgumentsSoftLimit) 字符）。\(writeToolGuidance)"
    }

    /// 整批预检：任一子调用命中写入超长 → 返回拦截文案；否则 nil。
    public static func batchWritePreflightIssue(calls: [(toolName: String, argumentsJSON: String)]) -> String? {
        for (index, item) in calls.enumerated() {
            if let issue = batchWritePreflightIssue(toolName: item.toolName, argumentsJSON: item.argumentsJSON, index: index) {
                return issue
            }
        }
        return nil
    }

    // MARK: - 内部：扫描与摘要

    private struct ScanOutcome {
        var issues: [ScanIssue] = []
        var isUnclosed = false
    }

    private enum ScanIssue: Equatable {
        case leadingGarbage(Int)
        case unclosedString(Int)
        case invalidEscape(Int)
        case controlCharacterInString(Int)
        case trailingComma(Int)
        case unexpectedClosing(Int)
        case unclosedContainer(Int)
    }

    private static let validEscapeSet: Set<Character> = ["\"", "\\", "/", "b", "f", "n", "r", "t", "u"]

    private static func scan(_ s: String) -> ScanOutcome {
        var outcome = ScanOutcome()
        let chars = Array(s)
        guard let first = chars.firstIndex(where: { !$0.isWhitespace }) else { return outcome }
        if chars[first] != "{" && chars[first] != "[" {
            outcome.issues.append(.leadingGarbage(first))
        }
        var stack: [(char: Character, offset: Int, lastWasComma: Bool)] = []
        var inString = false
        var stringStart = -1
        var escaped = false
        var index = 0
        for c in chars {
            if inString {
                if escaped {
                    escaped = false
                    if !validEscapeSet.contains(c) {
                        outcome.issues.append(.invalidEscape(index))
                    }
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                } else if c.isControl {
                    outcome.issues.append(.controlCharacterInString(index))
                }
                index += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                stringStart = index
            case "{", "[":
                stack.append((c, index, false))
            case "}", "]":
                guard let frame = stack.popLast() else {
                    outcome.issues.append(.unexpectedClosing(index))
                    break
                }
                if (frame.char == "{" ? c != "}" : c != "]") {
                    outcome.issues.append(.unexpectedClosing(index))
                }
                if frame.lastWasComma {
                    outcome.issues.append(.trailingComma(index))
                }
            case ",":
                if var top = stack.popLast() {
                    top.lastWasComma = true
                    stack.append(top)
                }
            default:
                if !c.isWhitespace, var top = stack.popLast() {
                    top.lastWasComma = false
                    stack.append(top)
                }
            }
            index += 1
        }
        if inString {
            outcome.issues.append(.unclosedString(max(stringStart, 0)))
            outcome.isUnclosed = true
        }
        if let frame = stack.last {
            outcome.issues.append(.unclosedContainer(frame.offset))
            outcome.isUnclosed = true
        }
        return outcome
    }

    private static func summarize(_ scan: ScanOutcome, truncated: Bool) -> (Int?, String) {
        guard let issue = scan.issues.min(by: { issueOffset($0) < issueOffset($1) }) else {
            return (nil, truncated ? "JSON 未闭合，疑似被截断" : "非法 JSON 语法")
        }
        let offset = issueOffset(issue)
        switch issue {
        case .leadingGarbage:
            return (offset, "JSON 不是以 { 或 [ 开头")
        case .unclosedString:
            return (offset, "字符串未闭合（缺少结尾引号）")
        case .invalidEscape:
            return (offset, "字符串内存在非法转义序列")
        case .controlCharacterInString:
            return (offset, "字符串内含未转义的控制字符")
        case .trailingComma:
            return (offset, "存在尾随逗号（逗号后紧跟 } 或 ]）")
        case .unexpectedClosing:
            return (offset, "存在多余的或配错的闭合括号")
        case .unclosedContainer:
            return (offset, "JSON 结构未闭合（缺少 } 或 ]）")
        }
    }

    private static func issueOffset(_ issue: ScanIssue) -> Int {
        switch issue {
        case .leadingGarbage(let o), .unclosedString(let o), .invalidEscape(let o),
             .controlCharacterInString(let o), .trailingComma(let o), .unexpectedClosing(let o),
             .unclosedContainer(let o):
            return o
        }
    }

    private static func lineColumn(of offset: Int, in s: String) -> (line: Int, column: Int) {
        var line = 1
        var column = 1
        var i = 0
        for c in s {
            if i == offset { break }
            if c == "\n" { line += 1; column = 1 } else { column += 1 }
            i += 1
        }
        return (line, column)
    }

    private static func escapedJSONString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                out += "\\\""
            case "\\":
                out += "\\\\"
            case "\n":
                out += "\\n"
            case "\r":
                out += "\\r"
            case "\t":
                out += "\\t"
            case "\u{08}":
                out += "\\b"
            case "\u{0C}":
                out += "\\f"
            case "\u{2028}", "\u{2029}":
                out += String(format: "\\u%04x", scalar.value)
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

private extension Character {
    var isControl: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return scalar.value < 0x20
    }
}
