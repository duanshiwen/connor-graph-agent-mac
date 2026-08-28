import Foundation
import Testing
import ConnorGraphAgent

private func makeToolTempWorkspace(_ name: String = UUID().uuidString) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-local-tool-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func readToolHonorsExplicitWindowOnSmallFile() async throws {
    // 显式窗口：即使小文件能整读，也必须从指定 offset 开始、按 limit 截取，不能从头返回全文。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("README.md")
    try "one\ntwo\nthree\nfour".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"README.md","offset":2,"limit":2}"#),
        context: .localToolTestContext(toolCallID: "read-small-window")
    )

    #expect(result.toolName == "Read")
    #expect(result.contentText.contains("2: two"))
    #expect(result.contentText.contains("3: three"))
    #expect(!result.contentText.contains("1: one"))
    #expect(!result.contentText.contains("4: four"))
    #expect(result.contentJSON?.contains(#""offset":2"#) == true)
    #expect(result.contentJSON?.contains(#""limit":2"#) == true)
    #expect(result.contentJSON?.contains(#""truncated":false"#) == true)
    #expect(result.contentJSON?.contains("nextOffset") == false)
}

@Test func readToolReturnsWholeSmallFileWhenNoWindow() async throws {
    // 无显式窗口：小文件整读仍返回全文，不压缩。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("README.md")
    try "one\ntwo\nthree\nfour".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"README.md"}"#),
        context: .localToolTestContext(toolCallID: "read-small-full")
    )

    #expect(result.contentText.contains("1: one"))
    #expect(result.contentText.contains("4: four"))
    #expect(result.contentJSON?.contains(#""offset":1"#) == true)
    #expect(result.contentJSON?.contains(#""limit":4"#) == true)
    #expect(result.contentJSON?.contains(#""truncated":false"#) == true)
}

@Test func readToolContinuesSmallFileFromOffsetWithoutLimit() async throws {
    // 只传 offset：从该行读到文件末尾。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("README.md")
    try "one\ntwo\nthree\nfour".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"README.md","offset":3}"#),
        context: .localToolTestContext(toolCallID: "read-small-offset")
    )

    #expect(result.contentText == "3: three\n4: four")
    #expect(result.contentJSON?.contains(#""offset":3"#) == true)
    #expect(result.contentJSON?.contains(#""limit":2"#) == true)
    #expect(result.contentJSON?.contains(#""truncated":false"#) == true)
}

@Test func readToolWindowFullyDeliveredOnLargeFileIsNotTruncated() async throws {
    // 大文件显式窗口完整送达：恰好返回 limit 行，不算截断，无 nextOffset。
    let (file, _) = try makeLargeReadableFile()
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: file.deletingLastPathComponent()))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"large.txt","offset":100,"limit":50}"#),
        context: .localToolTestContext(toolCallID: "read-large-window")
    )

    #expect(result.contentText.hasPrefix("100: line-100-"))
    #expect(result.contentText.contains("149: line-149-"))
    #expect(!result.contentText.contains("99: line-99-"))
    #expect(result.contentJSON?.contains(#""offset":100"#) == true)
    #expect(result.contentJSON?.contains(#""limit":50"#) == true)
    #expect(result.contentJSON?.contains(#""truncated":false"#) == true)
    #expect(result.contentJSON?.contains("nextOffset") == false)
}

@Test func readToolWindowBudgetTruncatedReturnsNextOffset() async throws {
    // 窗口未送完但输出预算先耗尽：标记 truncated 并返回 nextOffset 供续读。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("budget.txt")
    let content = (1...10).map { "line-\($0)-\(String(repeating: "x", count: 40))" }.joined(separator: "\n")
    try content.write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace, maxToolOutputBytes: 300))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"budget.txt","offset":1,"limit":10}"#),
        context: .localToolTestContext(toolCallID: "read-window-truncated")
    )

    #expect(result.contentText.hasPrefix("1: line-1-"))
    #expect(!result.contentText.contains("10: line-10-"))
    #expect(result.contentJSON?.contains(#""truncated":true"#) == true)
    #expect(result.contentJSON?.contains("nextOffset") == true)
}

private func makeLargeReadableFile(_ name: String = "large.txt") throws -> (URL, String) {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent(name)
    let content = (1...1_500).map { "line-\($0)-\(String(repeating: "x", count: 50))" }.joined(separator: "\n") + "\n"
    try content.write(to: file, atomically: true, encoding: .utf8)
    return (file, content)
}

@Test func readToolAutoTruncatesLargeFileAndReturnsNextOffset() async throws {
    // 大文件整读一次：按输出预算自动截断，并返回 nextOffset 供继续翻页。
    let (file, content) = try makeLargeReadableFile()
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: file.deletingLastPathComponent()))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"large.txt"}"#),
        context: .localToolTestContext(toolCallID: "read-large")
    )

    #expect(result.contentText.hasPrefix("1: line-1-"))
    #expect(!result.contentText.isEmpty)
    #expect(result.contentJSON?.contains(#""truncated":true"#) == true)
    #expect(result.contentJSON?.contains("nextOffset") == true)
    #expect(result.contentText.utf8.count <= 32 * 1_024)
}

@Test func readToolContinuesLargeFileFromNextOffset() async throws {
    // 大文件续读：从返回的 nextOffset 继续，内容从该行号开始且仍带截断标记。
    let (file, content) = try makeLargeReadableFile()
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: file.deletingLastPathComponent()))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"filePath":"large.txt","offset":100}"#),
        context: .localToolTestContext(toolCallID: "read-large-offset")
    )

    #expect(result.contentText.hasPrefix("100: line-100-"))
    #expect(result.contentJSON?.contains(#""truncated":true"#) == true)
}

@Test func listDirectoryToolReturnsSortedEntries() async throws {
    let workspace = try makeToolTempWorkspace()
    try "b".write(to: workspace.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    try "a".write(to: workspace.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    let tool = LocalListDirectoryTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"path":"."}"#),
        context: .localToolTestContext(toolCallID: "ls-1")
    )

    let aIndex = result.contentText.firstRange(of: "a.txt")?.lowerBound
    let bIndex = result.contentText.firstRange(of: "b.txt")?.lowerBound
    #expect(aIndex != nil && bIndex != nil)
    #expect(aIndex! < bIndex!)
    #expect(result.contentText.contains("Sources/"))
}

@Test func listDirectoryToolPaginatesWithOffsetAndLimit() async throws {
    let workspace = try makeToolTempWorkspace()
    try "a".write(to: workspace.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "b".write(to: workspace.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    try "c".write(to: workspace.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
    let tool = LocalListDirectoryTool(policy: LocalWorkspacePolicy(workingDirectory: workspace, maxSearchResults: 2))

    let first = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"path":"."}"#),
        context: .localToolTestContext(toolCallID: "ls-cursor-1")
    )
    #expect(first.contentText.contains("a.txt"))
    #expect(first.contentText.contains("b.txt"))
    #expect(!first.contentText.contains("c.txt"))
    #expect(first.contentJSON?.contains(#""truncated":true"#) == true)
    #expect(first.contentJSON?.contains(#""nextOffset":2"#) == true)

    let second = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"path":".","offset":2,"limit":2}"#),
        context: .localToolTestContext(toolCallID: "ls-cursor-2")
    )
    #expect(second.contentText.contains("c.txt"))
    #expect(!second.contentText.contains("a.txt"))
    #expect(second.contentJSON?.contains(#""truncated":false"#) == true)
}

@Test func globToolFindsMatchingFilesInsideWorkspace() async throws {
    let workspace = try makeToolTempWorkspace()
    let sources = workspace.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try "swift".write(to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    try "md".write(to: workspace.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    let tool = LocalGlobTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"**/*.swift","path":"."}"#),
        context: .localToolTestContext(toolCallID: "glob-1")
    )

    #expect(result.toolName == "Glob")
    #expect(result.contentText.contains("Sources/App.swift"))
    #expect(!result.contentText.contains("README.md"))
}

@Test func globToolPaginatesWithOffsetAndLimit() async throws {
    let workspace = try makeToolTempWorkspace()
    let sources = workspace.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try "1".write(to: sources.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
    try "2".write(to: sources.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
    try "3".write(to: sources.appendingPathComponent("C.swift"), atomically: true, encoding: .utf8)
    let tool = LocalGlobTool(policy: LocalWorkspacePolicy(workingDirectory: workspace, maxSearchResults: 2))

    let first = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"**/*.swift","path":"."}"#),
        context: .localToolTestContext(toolCallID: "glob-cursor-1")
    )
    #expect(first.contentText.contains("A.swift"))
    #expect(first.contentText.contains("B.swift"))
    #expect(!first.contentText.contains("C.swift"))
    #expect(first.contentJSON?.contains(#""nextOffset":2"#) == true)

    let second = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"**/*.swift","path":".","offset":2,"limit":2}"#),
        context: .localToolTestContext(toolCallID: "glob-cursor-2")
    )
    #expect(second.contentText.contains("C.swift"))
    #expect(!second.contentText.contains("A.swift"))
    #expect(second.contentJSON?.contains(#""truncated":false"#) == true)
}

@Test func grepToolSupportsLiteralContextAndTruncationMetadata() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("notes.txt")
    try "alpha\nbeta needle\ngamma\nneedle delta\n".write(to: file, atomically: true, encoding: .utf8)
    let policy = LocalWorkspacePolicy(workingDirectory: workspace, maxSearchResults: 1)
    let tool = LocalGrepTool(policy: policy)

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"needle","path":".","literal":true,"context":1}"#),
        context: .localToolTestContext(toolCallID: "grep-1")
    )

    #expect(result.toolName == "Grep")
    #expect(result.contentText.contains("notes.txt:2: beta needle"))
    #expect(result.contentText.contains("notes.txt:1- alpha"))
    #expect(result.contentJSON?.contains(#""truncated":true"#) == true)
}

@Test func grepToolPaginatesMatchesWithOffsetAndLimit() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("notes.txt")
    try "alpha needle\ndelta needle\ngamma needle\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalGrepTool(policy: LocalWorkspacePolicy(workingDirectory: workspace, maxSearchResults: 1))

    let middle = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"needle","path":".","literal":true,"offset":1,"limit":1}"#),
        context: .localToolTestContext(toolCallID: "grep-cursor-1")
    )
    #expect(middle.contentText.contains("notes.txt:2: delta needle"))
    #expect(!middle.contentText.contains("gamma needle"))
    #expect(middle.contentJSON?.contains(#""offset":1"#) == true)
    #expect(middle.contentJSON?.contains(#""truncated":true"#) == true)
    #expect(middle.contentJSON?.contains(#""nextOffset":2"#) == true)

    let tail = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"pattern":"needle","path":".","literal":true,"offset":2,"limit":1}"#),
        context: .localToolTestContext(toolCallID: "grep-cursor-2")
    )
    #expect(tail.contentText.contains("notes.txt:3: gamma needle"))
    #expect(tail.contentJSON?.contains(#""truncated":false"#) == true)
}

@Test func readToolAcceptsPathAlias() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("README.md")
    try "hello\nworld\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"path":"README.md"}"#),
        context: .localToolTestContext(toolCallID: "read-path")
    )

    #expect(result.contentText.contains("hello"))
}

@Test func applyPatchToolAcceptsLegacyAliasesInOperations() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\nlet b = 2\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operations":[{"op":"edit","path":"App.swift","old_string":"let a = 1","new_string":"let a = 10"}]}"#),
        context: .localToolTestContext(toolCallID: "patch-alias")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 10\nlet b = 2\n")
}

@Test func applyPatchToolNormalizesAddPathValueToCreate() async throws {
    // 真实使用中模型常把整文件创建写成 op=add + path + value；归一化后应能正常建文件。
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: #"{"operations":[{"op":"add","path":"notes.md","value":"hello\n"}]}"#
        ),
        context: .localToolTestContext(toolCallID: "patch-add-value")
    )

    #expect(try String(contentsOf: workspace.appendingPathComponent("notes.md"), encoding: .utf8) == "hello\n")
}

@Test func applyPatchToolInfersMissingOpAsCreate() async throws {
    // 模型有时漏写 op，只给 filePath + content；应按 create 处理而不是报 “op is required”。
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: ##"{"operations":[{"filePath":"readme.md","content":"# Hi\n"}]}"##
        ),
        context: .localToolTestContext(toolCallID: "patch-missing-op")
    )

    #expect(try String(contentsOf: workspace.appendingPathComponent("readme.md"), encoding: .utf8) == "# Hi\n")
}

@Test func applyPatchToolAcceptsTopLevelOpAsSingleOperation() async throws {
    // 模型把单个 operation 展开到顶层（op + path + value）时，应自动包成 operations 数组并完成创建。
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: ##"{"op":"create","path":"notes.md","value":"hello\n"}"##
        ),
        context: .localToolTestContext(toolCallID: "patch-top-level-create")
    )

    #expect(try String(contentsOf: workspace.appendingPathComponent("notes.md"), encoding: .utf8) == "hello\n")
}

@Test func applyPatchToolAcceptsTopLevelReplaceAsEdit() async throws {
    // 顶层 op=replace + old_string/new_string 展开写法应归一到 edit 并完成唯一替换。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: #"{"op":"replace","path":"App.swift","old_string":"let a = 1","new_string":"let a = 10"}"#
        ),
        context: .localToolTestContext(toolCallID: "patch-top-level-replace")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 10\n")
}

@Test func applyPatchToolAcceptsOperationsAsSingleObject() async throws {
    // operations 写成对象而不是数组时，也应自动包成数组并完成创建。
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: ##"{"operations":{"op":"create","filePath":"readme.md","content":"# Hi\n"}}"##
        ),
        context: .localToolTestContext(toolCallID: "patch-operations-object")
    )

    #expect(try String(contentsOf: workspace.appendingPathComponent("readme.md"), encoding: .utf8) == "# Hi\n")
}

@Test func applyPatchToolAddsCorrectiveHintWhenOperationsMissing() async throws {
    // 完全无法推断 op 的调用仍然失败，但错误信息要给出可执行的修正示例，
    // 避免模型在“schema 说 op 必填、报错却说 op 不支持”的矛盾里反复重试。
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    do {
        _ = try await registry.execute(
            AgentToolCall(
                name: "ApplyPatch",
                argumentsJSON: #"{"note":"please write a file"}"#
            ),
            context: .localToolTestContext(toolCallID: "patch-hint")
        )
        Issue.record("Expected ApplyPatch to reject arguments without operations")
    } catch {
        let text = String(describing: error)
        #expect(text.contains("operations"))
        #expect(text.contains("Correct example"))
        #expect(text.contains("\"op\":\"create\""))
    }
}

@Test func applyPatchToolNormalizesReplaceToEdit() async throws {
    // 模型把替换写成 op=replace + path + value 时，应归一到 edit 并完成唯一替换。
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var registry = AgentToolRegistry()
    registry.register(tool)

    _ = try await registry.execute(
        AgentToolCall(
            name: "ApplyPatch",
            argumentsJSON: #"{"operations":[{"op":"replace","path":"App.swift","old_string":"let a = 1","new_string":"let a = 10"}]}"#
        ),
        context: .localToolTestContext(toolCallID: "patch-replace-edit")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 10\n")
}

@Test func readManyToolReadsMultipleFilesInRequestOrder() async throws {
    let workspace = try makeToolTempWorkspace()
    try "alpha\nbeta\n".write(to: workspace.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "one\ntwo\nthree\nfour\n".write(to: workspace.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    let tool = LocalReadManyTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"requests":[{"filePath":"a.txt"},{"filePath":"b.txt","offset":2,"limit":2}]}"#),
        context: .localToolTestContext(toolCallID: "readmany-1")
    )

    #expect(result.toolName == "ReadMany")
    #expect(result.error == nil)
    let aIndex = result.contentText.firstRange(of: "a.txt")?.lowerBound
    let bIndex = result.contentText.firstRange(of: "b.txt")?.lowerBound
    #expect(aIndex != nil && bIndex != nil)
    #expect(aIndex! < bIndex!)
    #expect(result.contentText.contains("1: alpha"))
    #expect(result.contentText.contains("2: two"))
    #expect(result.contentText.contains("3: three"))
    #expect(!result.contentText.contains("1: one"))
}

@Test func readManyToolReportsNextOffsetForTruncatedWindows() async throws {
    let workspace = try makeToolTempWorkspace()
    try "one\ntwo\nthree\nfour\n".write(to: workspace.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    let tool = LocalReadManyTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"requests":[{"filePath":"b.txt","offset":1,"limit":2}]}"#),
        context: .localToolTestContext(toolCallID: "readmany-cursor")
    )

    #expect(result.contentText.contains("1: one"))
    #expect(result.contentText.contains("2: two"))
    #expect(result.contentText.contains(#""truncated":true"#))
    #expect(result.contentText.contains(#""nextOffset":3"#))
}

@Test func readManyToolReportsPerFileErrorWithoutFailingBatch() async throws {
    let workspace = try makeToolTempWorkspace()
    try "present\n".write(to: workspace.appendingPathComponent("here.txt"), atomically: true, encoding: .utf8)
    let tool = LocalReadManyTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"requests":[{"filePath":"here.txt"},{"filePath":"missing.txt"}]}"#),
        context: .localToolTestContext(toolCallID: "readmany-partial")
    )

    // One good read means the whole batch still succeeds; the missing file is
    // reported as a per-item error inside the JSON payload.
    #expect(result.error == nil)
    #expect(result.contentText.contains("present"))
    #expect(result.contentText.contains("\"error\""))
}

@Test func readManyToolRejectsPathEscapeAsPerFileError() async throws {
    let workspace = try makeToolTempWorkspace()
    let tool = LocalReadManyTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"requests":[{"filePath":"../../etc/hosts"}]}"#),
        context: .localToolTestContext(toolCallID: "readmany-escape")
    )

    // Every request failed, so the batch surfaces an error, and the escape is
    // recorded as a per-item error rather than reading outside the workspace.
    #expect(result.error != nil)
    #expect(result.contentText.contains("\"error\""))
}

@Test func applyPatchToolAppliesCreateThenEditInOrder() async throws {
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operations":[{"op":"create","filePath":"Sources/New.swift","content":"let value = 1\n"},{"op":"edit","filePath":"Sources/New.swift","oldText":"let value = 1","newText":"let value = 2"}]}"#),
        context: .localToolTestContext(toolCallID: "writebatch-1")
    )

    let file = workspace.appendingPathComponent("Sources/New.swift")
    #expect(try String(contentsOf: file, encoding: .utf8) == "let value = 2\n")
    #expect(result.toolName == "ApplyPatch")
    #expect(result.contentJSON?.contains("\"success\":true") == true)
}

@Test func applyPatchToolDoesNotCommitWhenValidationFails() async throws {
    let workspace = try makeToolTempWorkspace()
    let existing = workspace.appendingPathComponent("Existing.swift")
    try "let a = 1\n".write(to: existing, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: AgentToolError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"operations":[{"op":"create","filePath":"Fresh.swift","content":"new\n"},{"op":"edit","filePath":"Existing.swift","oldText":"missing","newText":"x"}]}"#),
            context: .localToolTestContext(toolCallID: "writebatch-atomic")
        )
    }

    // The failing edit must roll back the whole batch: the create is never
    // committed and the existing file is untouched.
    #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Fresh.swift").path))
    #expect(try String(contentsOf: existing, encoding: .utf8) == "let a = 1\n")
}

@Test func applyPatchToolRejectsOverlappingEditsOnSameFile() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: AgentToolError.self) {
        // The second edit's oldText no longer exists in the projected copy
        // produced by the first edit, so the conflict is caught before commit.
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"operations":[{"op":"edit","filePath":"App.swift","oldText":"let a = 1","newText":"let a = 2"},{"op":"edit","filePath":"App.swift","oldText":"let a = 1","newText":"let a = 3"}]}"#),
            context: .localToolTestContext(toolCallID: "writebatch-conflict")
        )
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 1\n")
}

@Test func applyPatchToolRequiresUniqueOldTextByDefault() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\nlet a = 2\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: AgentToolError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"operations":[{"op":"edit","filePath":"App.swift","oldText":"let a =","newText":"let b ="}]}"#),
            context: .localToolTestContext(toolCallID: "applypatch-ambiguous")
        )
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 1\nlet a = 2\n")
}

@Test func applyPatchToolReplaceAllReplacesEveryOccurrence() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\nlet a = 2\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    _ = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operations":[{"op":"edit","filePath":"App.swift","oldText":"let a =","newText":"let b =","replaceAll":true}]}"#),
        context: .localToolTestContext(toolCallID: "applypatch-replace-all")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "let b = 1\nlet b = 2\n")
}

@Test func applyPatchToolMultieditSupportsReplaceAllAliases() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "oldName(1)\noldName(2)\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    _ = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operations":[{"op":"multiedit","filePath":"App.swift","edits":[{"old_string":"oldName(","new_string":"newName(","allow_multiple":true}]}]}"#),
        context: .localToolTestContext(toolCallID: "applypatch-multiedit-replace-all")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "newName(1)\nnewName(2)\n")
}

@Test func applyPatchToolDeletesExistingFile() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    _ = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operations":[{"op":"delete","filePath":"App.swift"}]}"#),
        context: .localToolTestContext(toolCallID: "applypatch-delete")
    )

    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func applyPatchApprovalPayloadListsEveryOperation() async throws {
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var call = AgentToolCall(
        id: "writebatch-approval",
        name: "ApplyPatch",
        argumentsJSON: #"{"operations":[{"op":"create","filePath":"A.swift","content":"a"},{"op":"edit","filePath":"B.swift","oldText":"x","newText":"y"}]}"#
    )
    call.runID = "run-local-tools"

    let payload = await tool.approvalPayloadJSON(
        for: call,
        context: .localToolTestContext(toolCallID: "writebatch-approval")
    )

    #expect(payload.contains("A.swift"))
    #expect(payload.contains("B.swift"))
    #expect(payload.contains("create"))
    #expect(payload.contains("edit"))
}

@Test func applyPatchApprovalPayloadIncludesInstruction() async throws {
    let workspace = try makeToolTempWorkspace()
    let tool = LocalApplyPatchTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    var call = AgentToolCall(
        id: "writebatch-instruction",
        name: "ApplyPatch",
        argumentsJSON: #"{"operations":[{"op":"edit","filePath":"B.swift","oldText":"x","newText":"y","instruction":"将占位符替换为正式值"}]}"#
    )
    call.runID = "run-local-tools"

    let payload = await tool.approvalPayloadJSON(
        for: call,
        context: .localToolTestContext(toolCallID: "writebatch-instruction")
    )

    #expect(payload.contains("B.swift"))
    #expect(payload.contains("将占位符替换为正式值"))
}

private extension AgentToolExecutionContext {
    static func localToolTestContext(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-local-tools",
            sessionID: "session-local-tools",
            groupID: "default",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }
}
