import Foundation
import Testing
import ConnorGraphAgent

private func makeToolTempWorkspace(_ name: String = UUID().uuidString) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-local-tool-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func readToolReturnsFileContentWithLineWindow() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("README.md")
    try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalReadFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"file_path":"README.md","offset":2,"limit":2}"#),
        context: .localToolTestContext(toolCallID: "read-1")
    )

    #expect(result.toolName == "Read")
    #expect(result.contentText.contains("2: two"))
    #expect(result.contentText.contains("3: three"))
    #expect(!result.contentText.contains("1: one"))
    #expect(result.contentJSON?.contains("truncated") == true)
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

@Test func writeToolCreatesWorkspaceFile() async throws {
    let workspace = try makeToolTempWorkspace()
    let tool = LocalWriteFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"file_path":"Sources/New.swift","content":"let value = 42\n"}"#),
        context: .localToolTestContext(toolCallID: "write-1")
    )

    let file = workspace.appendingPathComponent("Sources/New.swift")
    #expect(try String(contentsOf: file, encoding: .utf8) == "let value = 42\n")
    #expect(result.toolName == "Write")
    #expect(result.contentText.contains("created"))
}

@Test func editToolRequiresUniqueOldText() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\nlet a = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalEditFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: AgentToolError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"file_path":"App.swift","old_text":"let a = 1","new_text":"let a = 2"}"#),
            context: .localToolTestContext(toolCallID: "edit-dup")
        )
    }
}

@Test func editToolReplacesUniqueOldText() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "let a = 1\nlet b = 2\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalEditFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"file_path":"App.swift","old_text":"let a = 1","new_text":"let a = 10"}"#),
        context: .localToolTestContext(toolCallID: "edit-1")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "let a = 10\nlet b = 2\n")
    #expect(result.contentJSON?.contains("beforeHash") == true)
}

@Test func multiEditToolAppliesAtomically() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalMultiEditTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"file_path":"App.swift","edits":[{"old_text":"one","new_text":"ONE"},{"old_text":"three","new_text":"THREE"}]}"#),
        context: .localToolTestContext(toolCallID: "multi-1")
    )

    #expect(try String(contentsOf: file, encoding: .utf8) == "ONE\ntwo\nTHREE\n")
    #expect(result.contentText.contains("2 edits"))
}

@Test func multiEditToolDoesNotPartiallyWriteWhenInvalid() async throws {
    let workspace = try makeToolTempWorkspace()
    let file = workspace.appendingPathComponent("App.swift")
    try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
    let tool = LocalMultiEditTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: AgentToolError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"file_path":"App.swift","edits":[{"old_text":"one","new_text":"ONE"},{"old_text":"missing","new_text":"MISSING"}]}"#),
            context: .localToolTestContext(toolCallID: "multi-invalid")
        )
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "one\ntwo\n")
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
