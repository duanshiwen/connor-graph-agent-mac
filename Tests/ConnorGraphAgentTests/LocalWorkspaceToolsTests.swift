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
        arguments: try AgentToolArguments(json: #"{"filePath":"README.md","offset":2,"limit":2}"#),
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
        arguments: try AgentToolArguments(json: #"{"filePath":"Sources/New.swift","content":"let value = 42\n"}"#),
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
            arguments: try AgentToolArguments(json: #"{"filePath":"App.swift","oldText":"let a = 1","newText":"let a = 2"}"#),
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
        arguments: try AgentToolArguments(json: #"{"filePath":"App.swift","oldText":"let a = 1","newText":"let a = 10"}"#),
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
        arguments: try AgentToolArguments(json: #"{"filePath":"App.swift","edits":[{"oldText":"one","newText":"ONE"},{"oldText":"three","newText":"THREE"}]}"#),
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

    do {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"filePath":"App.swift","edits":[{"oldText":"one","newText":"ONE"},{"oldText":"missing","newText":"MISSING"}]}"#),
            context: .localToolTestContext(toolCallID: "multi-invalid")
        )
        Issue.record("Expected an invalidArguments error")
    } catch let error as AgentToolError {
        #expect(error.description.contains("oldText must occur exactly once"))
        #expect(!error.description.contains("old_text"))
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "one\ntwo\n")
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
