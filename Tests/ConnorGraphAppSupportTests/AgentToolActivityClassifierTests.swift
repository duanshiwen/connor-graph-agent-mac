import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphAgent

@Test func classifiesReadToolAsReadFileWithTargetAndIcon() {
    let call = AgentToolCall(
        id: "read-1",
        runID: "run",
        sessionID: "session",
        name: "Read",
        argumentsJSON: "{\"file_path\":\"Sources/ConnorGraphAgentMac/AgentChatActivityViews.swift\",\"offset\":596,\"limit\":270}"
    )

    let activity = AgentToolActivityClassifier().activity(forRequestedCall: call)

    #expect(activity?.semanticKind == .readFile)
    #expect(activity?.title == "Read File")
    #expect(activity?.target == "AgentChatActivityViews.swift")
    #expect(activity?.subtitle == "596–865")
    #expect(activity?.icon == "doc.text.magnifyingglass")
}

@Test func classifiesWriteToolAsWriteFileWithPencilIcon() {
    let call = AgentToolCall(
        id: "write-1",
        name: "Write",
        argumentsJSON: "{\"file_path\":\"README.md\",\"content\":\"hello\"}"
    )

    let activity = AgentToolActivityClassifier().activity(forRequestedCall: call)

    #expect(activity?.semanticKind == .writeFile)
    #expect(activity?.title == "Write File")
    #expect(activity?.target == "README.md")
    #expect(activity?.icon == "square.and.pencil")
}

@Test func classifiesEditResultWithEditCount() {
    let result = AgentToolResult(
        toolCallID: "edit-1",
        toolName: "MultiEdit",
        contentText: "Applied 3 edits to file: /tmp/BrowserHistoryPanelView.swift",
        contentJSON: "{\"path\":\"/tmp/BrowserHistoryPanelView.swift\",\"edits\":3}"
    )

    let activity = AgentToolActivityClassifier().activity(forFinishedResult: result)

    #expect(activity?.semanticKind == .editFile)
    #expect(activity?.title == "Edit File")
    #expect(activity?.target == "BrowserHistoryPanelView.swift")
    #expect(activity?.subtitle == "3 edits")
    #expect(activity?.icon == "pencil")
}

@Test func classifiesSwiftBuildAndSwiftTestBashCommands() {
    let build = AgentToolCall(
        id: "bash-build",
        name: "Bash",
        argumentsJSON: "{\"command\":\"cd /repo && swift build 2>&1 | tee build.log\"}"
    )
    let test = AgentToolCall(
        id: "bash-test",
        name: "Bash",
        argumentsJSON: "{\"command\":\"swift test --filter AgentToolActivityClassifierTests\"}"
    )

    let classifier = AgentToolActivityClassifier()
    let buildActivity = classifier.activity(forRequestedCall: build)
    let testActivity = classifier.activity(forRequestedCall: test)

    #expect(buildActivity?.semanticKind == .swiftBuild)
    #expect(buildActivity?.title == "Swift: 编译项目")
    #expect(buildActivity?.target == "swift build")
    #expect(buildActivity?.icon == "swift")

    #expect(testActivity?.semanticKind == .swiftTest)
    #expect(testActivity?.title == "Swift: 运行测试")
    #expect(testActivity?.target == "swift test")
    #expect(testActivity?.icon == "swift")
}

@Test func classifiesGitDiffBashCommand() {
    let call = AgentToolCall(
        id: "bash-git",
        name: "Bash",
        argumentsJSON: "{\"command\":\"git diff -- Sources/ConnorGraphAppSupport\"}"
    )

    let activity = AgentToolActivityClassifier().activity(forRequestedCall: call)

    #expect(activity?.semanticKind == .git)
    #expect(activity?.title == "Git: 查看变更")
    #expect(activity?.target == "git diff")
    #expect(activity?.icon == "arrow.triangle.branch")
}

@Test func classifiesSearchAndDirectoryTools() {
    let grep = AgentToolCall(id: "grep-1", name: "Grep", argumentsJSON: "{\"pattern\":\"Tool\",\"path\":\"Sources\"}")
    let glob = AgentToolCall(id: "glob-1", name: "Glob", argumentsJSON: "{\"pattern\":\"**/*.swift\",\"path\":\"Sources\"}")
    let ls = AgentToolCall(id: "ls-1", name: "LS", argumentsJSON: "{\"path\":\"Sources\"}")

    let classifier = AgentToolActivityClassifier()

    #expect(classifier.activity(forRequestedCall: grep)?.title == "Search Files")
    #expect(classifier.activity(forRequestedCall: grep)?.icon == "magnifyingglass")
    #expect(classifier.activity(forRequestedCall: glob)?.title == "Find Files")
    #expect(classifier.activity(forRequestedCall: glob)?.icon == "scope")
    #expect(classifier.activity(forRequestedCall: ls)?.title == "List Directory")
    #expect(classifier.activity(forRequestedCall: ls)?.icon == "folder")
}

@Test func classifiesMCPToolsAndUnknownTools() {
    let mcp = AgentToolCall(id: "mcp-1", name: "mcp__kb-source__kb_search", argumentsJSON: "{\"query\":\"Connor\"}")
    let unknown = AgentToolCall(id: "unknown-1", name: "custom_tool", argumentsJSON: "{}")

    let classifier = AgentToolActivityClassifier()
    let mcpActivity = classifier.activity(forRequestedCall: mcp)
    let unknownActivity = classifier.activity(forRequestedCall: unknown)

    #expect(mcpActivity?.semanticKind == .mcp)
    #expect(mcpActivity?.title == "MCP: kb-source")
    #expect(mcpActivity?.target == "kb_search")
    #expect(mcpActivity?.icon == "server.rack")

    #expect(unknownActivity?.semanticKind == .unknown)
    #expect(unknownActivity?.title == "custom_tool")
    #expect(unknownActivity?.icon == "wrench.and.screwdriver")
}

@Test func classifiesCalendarMutationRequestsAndFailures() {
    let call = AgentToolCall(id: "calendar-write", name: "calendar_write", argumentsJSON: "{\"operation\":\"create_event\",\"calendarID\":\"default\"}")
    let failure = AgentToolFailure(runID: "run", sessionID: "session", toolCallID: call.id, toolName: call.name, message: "Invalid arguments: Calendar 'default' was not found")
    let classifier = AgentToolActivityClassifier()

    let requested = classifier.activity(forRequestedCall: call)
    let failed = classifier.activity(forFailure: failure)
    #expect(requested?.semanticKind == .calendar)
    #expect(requested?.title == "Calendar: Create Event")
    #expect(requested?.target == "default")
    #expect(failed?.semanticKind == .calendar)
    #expect(failed?.phase == .failed)
    #expect(failed?.detail?.contains("Calendar 'default' was not found") == true)
}

@Test func failedResultUsesErrorSeverityAndXmarkIcon() {
    let failure = AgentToolFailure(
        runID: "run",
        sessionID: "session",
        toolCallID: "bash-fail",
        toolName: "Bash",
        message: "Command exited with code 1"
    )

    let activity = AgentToolActivityClassifier().activity(forFailure: failure)

    #expect(activity?.phase == .failed)
    #expect(activity?.severity == .error)
    #expect(activity?.icon == "xmark.octagon")
}
