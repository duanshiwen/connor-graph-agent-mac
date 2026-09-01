import Foundation
import Testing
import ConnorGraphAgent

@Suite struct ToolArgumentJSONDiagnosticsTests {
    @Test func validObjectAnalyzesAsNil() {
        #expect(ToolArgumentJSONDiagnostics.analyze(#"{"operations":[{"op":"create","filePath":"a.md","content":"hi"}]}"#) == nil)
    }

    @Test func validEmptyObjectAnalyzesAsNil() {
        #expect(ToolArgumentJSONDiagnostics.analyze("{}") == nil)
    }

    @Test func arrayIsNotJSONObject() {
        let payload = ToolArgumentJSONDiagnostics.analyze("[1,2,3]")
        #expect(payload != nil)
        #expect(payload?.summary.contains("不是 JSON 对象") == true)
        #expect(payload?.truncated == false)
    }

    // 本管线用 JSONSerialization 解析，它实际容忍尾随逗号（{"a":1,} 能解析成功），
    // 因此尾随逗号单独出现不应被判非法——诊断器必须与解析器行为一致。
    @Test func trailingCommaAloneIsToleratedByParser() {
        #expect(ToolArgumentJSONDiagnostics.analyze(#"{"a":1,}"#) == nil)
    }

    // 仅当整个文档因其它原因非法且首个问题恰为尾随逗号时，才给出该分类。
    @Test func trailingCommaSurfacesWhenDocumentIsInvalid() {
        let payload = ToolArgumentJSONDiagnostics.analyze("[1,2,]x")
        #expect(payload != nil)
        #expect(payload?.summary.contains("尾随逗号") == true)
    }

    @Test func leadingGarbageDetected() {
        let payload = ToolArgumentJSONDiagnostics.analyze("not json at all")
        #expect(payload != nil)
        #expect(payload?.summary.contains("以 { 或 [ 开头") == true)
    }

    @Test func longUnclosedJSONIsLikelyTruncated() {
        let content = String(repeating: "字", count: 300)
        let json = #"{"operations":[{"op":"create","filePath":"a.md","content":""# + content + "\""
        let payload = ToolArgumentJSONDiagnostics.analyze(json)
        #expect(payload != nil)
        #expect(payload?.truncated == true)
        #expect(payload?.length == json.count)
        #expect(payload?.summary.contains("未闭合") == true)
    }

    @Test func shortUnclosedJSONIsSyntaxErrorNotTruncated() {
        let payload = ToolArgumentJSONDiagnostics.analyze(#"{"a": "unterminated"#)
        #expect(payload != nil)
        #expect(payload?.truncated == false)
    }

    @Test func invalidEscapeIsSyntaxError() {
        let payload = ToolArgumentJSONDiagnostics.analyze(#"{"a":"\q"}"#)
        #expect(payload != nil)
        #expect(payload?.summary.contains("非法转义") == true)
    }

    @Test func controlCharacterInStringIsSyntaxError() {
        let payload = ToolArgumentJSONDiagnostics.analyze("{\"a\":\"x\u{0001}y\"}")
        #expect(payload != nil)
        #expect(payload?.summary.contains("控制字符") == true)
    }

    @Test func markerRoundTripsRawContent() {
        let raw = #"{"operations":[{"op":"create","content":""# + String(repeating: "x", count: 300) + "\""
        let payload = ToolArgumentJSONDiagnostics.JSONErrorPayload(
            raw: raw,
            length: raw.count,
            truncated: true,
            summary: "未闭合",
            offset: 3,
            line: 1,
            column: 4
        )
        let marker = ToolArgumentJSONDiagnostics.invalidJSONMarker(payload: payload)
        #expect(marker.contains("INVALID_JSON") == true)
        let unwrapped = ToolArgumentJSONDiagnostics.unwrapInvalidJSONMarker(marker)
        #expect(unwrapped?.raw == raw)
        #expect(unwrapped?.truncated == true)
        #expect(unwrapped?.length == raw.count)
        #expect(unwrapped?.summary == "未闭合")
        #expect(unwrapped?.offset == 3)
        #expect(unwrapped?.line == 1)
        #expect(unwrapped?.column == 4)
    }

    @Test func markerEscapesControlCharactersInRaw() {
        let raw = "{\"a\":\"x\u{0001}y\"}"
        let marker = ToolArgumentJSONDiagnostics.invalidJSONMarker(
            payload: ToolArgumentJSONDiagnostics.JSONErrorPayload(raw: raw, length: raw.count, truncated: false, summary: "控制字符")
        )
        // 标记本身必须是合法 JSON，且原文（含控制字符）能无损解包。
        let unwrapped = ToolArgumentJSONDiagnostics.unwrapInvalidJSONMarker(marker)
        #expect(unwrapped?.raw == raw)
        #expect(ToolArgumentJSONDiagnostics.analyze(marker) == nil)
    }

    @Test func errorDescriptionGuidesWriteToolAwayFromBatch() {
        let payload = ToolArgumentJSONDiagnostics.JSONErrorPayload(
            raw: "x", length: 5000, truncated: true, summary: "未闭合"
        )
        let message = ToolArgumentJSONDiagnostics.errorDescription(forToolName: "ApplyPatch", payload: payload)
        #expect(message.contains("截断"))
        #expect(message.contains("请勿使用批量通道"))
        #expect(message.contains("直接调用 ApplyPatch"))
    }

    @Test func errorDescriptionIncludesPositionForSyntaxError() {
        let payload = ToolArgumentJSONDiagnostics.JSONErrorPayload(
            raw: "x", length: 10, truncated: false, summary: "尾随逗号", offset: 7, line: 1, column: 8
        )
        let message = ToolArgumentJSONDiagnostics.errorDescription(forToolName: "Read", payload: payload)
        #expect(message.contains("第 1 行第 8 列"))
        #expect(message.contains("尾随逗号"))
    }

    @Test func batchPreflightBlocksOversizedWriteTool() {
        let big = String(repeating: "a", count: ToolArgumentJSONDiagnostics.toolArgumentsSoftLimit + 10)
        let issue = ToolArgumentJSONDiagnostics.batchWritePreflightIssue(toolName: "ApplyPatch", argumentsJSON: big, index: 2)
        #expect(issue != nil)
        #expect(issue?.contains("calls[2]") == true)
        #expect(issue?.contains("ApplyPatch") == true)
    }

    @Test func batchPreflightAllowsNormalSizeWriteTool() {
        let issue = ToolArgumentJSONDiagnostics.batchWritePreflightIssue(
            toolName: "ApplyPatch", argumentsJSON: #"{"operations":[]}"#, index: 0
        )
        #expect(issue == nil)
    }

    @Test func batchPreflightIgnoresNonWriteTools() {
        let big = String(repeating: "a", count: ToolArgumentJSONDiagnostics.toolArgumentsSoftLimit + 10)
        #expect(ToolArgumentJSONDiagnostics.batchWritePreflightIssue(toolName: "note_search", argumentsJSON: big, index: 0) == nil)
    }

    @Test func batchPreflightScansWholeBatch() {
        let big = String(repeating: "b", count: ToolArgumentJSONDiagnostics.toolArgumentsSoftLimit + 10)
        let issue = ToolArgumentJSONDiagnostics.batchWritePreflightIssue(calls: [
            (toolName: "note_search", argumentsJSON: "{}"),
            (toolName: "applypatch", argumentsJSON: big),
            (toolName: "Read", argumentsJSON: "{}")
        ])
        #expect(issue?.contains("calls[1]") == true)
    }
}
