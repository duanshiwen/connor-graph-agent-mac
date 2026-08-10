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
        argumentsJSON: "{\"filePath\":\"Sources/ConnorGraphAgentMac/AgentChatActivityViews.swift\",\"offset\":596,\"limit\":270}"
    )

    let activity = AgentToolActivityClassifier().activity(forRequestedCall: call)

    #expect(activity?.semanticKind == .readFile)
    #expect(activity?.title == "读取文件")
    #expect(activity?.target == "AgentChatActivityViews.swift")
    #expect(activity?.subtitle == "596–865")
    #expect(activity?.icon == "doc.text.magnifyingglass")
}

@Test func classifiesWriteToolAsWriteFileWithPencilIcon() {
    let call = AgentToolCall(
        id: "write-1",
        name: "Write",
        argumentsJSON: "{\"filePath\":\"README.md\",\"content\":\"hello\"}"
    )

    let activity = AgentToolActivityClassifier().activity(forRequestedCall: call)

    #expect(activity?.semanticKind == .writeFile)
    #expect(activity?.title == "写入文件")
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
    #expect(activity?.title == "编辑文件")
    #expect(activity?.target == "BrowserHistoryPanelView.swift")
    #expect(activity?.subtitle == "3 处修改")
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

@Test func classifiesShellAndApplyPatchTools() {
    let shell = AgentToolCall(
        id: "shell-search",
        name: "Shell",
        argumentsJSON: #"{"command":"rg -n \"AgentLoop\" Sources"}"#
    )
    let patch = AgentToolResult(
        toolCallID: "apply-patch",
        toolName: "ApplyPatch",
        contentText: "Applied 3 operations across 2 files.",
        contentJSON: #"{"filesChanged":2,"operations":3}"#
    )

    let classifier = AgentToolActivityClassifier()
    let shellActivity = classifier.activity(forRequestedCall: shell)
    let patchActivity = classifier.activity(forFinishedResult: patch)

    #expect(shellActivity?.semanticKind == .searchFiles)
    #expect(shellActivity?.title == "Shell: 搜索文本")
    #expect(shellActivity?.icon == "magnifyingglass")

    #expect(patchActivity?.semanticKind == .editFile)
    #expect(patchActivity?.title == "应用补丁")
    #expect(patchActivity?.target == "2 个文件")
    #expect(patchActivity?.subtitle == "3 个操作")
    #expect(patchActivity?.icon == "doc.badge.gearshape")
}

@Test func classifiesSearchAndDirectoryTools() {
    let grep = AgentToolCall(id: "grep-1", name: "Grep", argumentsJSON: "{\"pattern\":\"Tool\",\"path\":\"Sources\"}")
    let glob = AgentToolCall(id: "glob-1", name: "Glob", argumentsJSON: "{\"pattern\":\"**/*.swift\",\"path\":\"Sources\"}")
    let ls = AgentToolCall(id: "ls-1", name: "LS", argumentsJSON: "{\"path\":\"Sources\"}")

    let classifier = AgentToolActivityClassifier()

    #expect(classifier.activity(forRequestedCall: grep)?.title == "搜索文件内容")
    #expect(classifier.activity(forRequestedCall: grep)?.icon == "magnifyingglass")
    #expect(classifier.activity(forRequestedCall: glob)?.title == "查找文件")
    #expect(classifier.activity(forRequestedCall: glob)?.icon == "scope")
    #expect(classifier.activity(forRequestedCall: ls)?.title == "查看目录")
    #expect(classifier.activity(forRequestedCall: ls)?.icon == "folder")
}

@Test func classifiesMCPToolsAndUnknownTools() {
    let mcp = AgentToolCall(id: "mcp-1", name: "mcp__kb-source__kb_search", argumentsJSON: "{\"query\":\"Connor\"}")
    let unknown = AgentToolCall(id: "unknown-1", name: "custom_tool", argumentsJSON: "{}")

    let classifier = AgentToolActivityClassifier()
    let mcpActivity = classifier.activity(forRequestedCall: mcp)
    let unknownActivity = classifier.activity(forRequestedCall: unknown)

    #expect(mcpActivity?.semanticKind == .mcp)
    #expect(mcpActivity?.title == "mcp__kb-source__kb_search")
    #expect(mcpActivity?.target == "kb_search")
    #expect(mcpActivity?.subtitle == "MCP · kb-source")
    #expect(mcpActivity?.icon == "server.rack")

    #expect(unknownActivity?.semanticKind == .unknown)
    #expect(unknownActivity?.title == "custom_tool")
    #expect(unknownActivity?.icon == "wrench.and.screwdriver")
}

@Test func batchToolsExposeExactNativeNamesAndCategories() {
    let classifier = AgentToolActivityClassifier()
    let query = AgentToolCall(
        id: "batch-query",
        name: "parallel_tool_query",
        argumentsJSON: #"{"calls":[{"toolName":"mcp__lark__search","arguments":{}},{"toolName":"cloud_kb_knowledge_context","arguments":{}},{"toolName":"mail_search_messages","arguments":{}}]}"#
    )
    let queryActivity = classifier.activity(forRequestedCall: query)
    #expect(queryActivity?.semanticKind == .parallelQuery)
    #expect(queryActivity?.title == "mcp__lark__search、查询知识库知识、搜索邮件")
    #expect(queryActivity?.subtitle == "并行查询 · MCP · 知识库 · 邮件")

    let execution = AgentToolResult(
        toolCallID: "batch-execute",
        toolName: "parallel_tool_execute",
        contentText: "done",
        contentJSON: #"{"results":[{"sourceID":"WriteBatch","title":"WriteBatch","summary":"done"},{"sourceID":"calendar_write","title":"calendar_write","summary":"done"}]}"#
    )
    let executionActivity = classifier.activity(forFinishedResult: execution)
    #expect(executionActivity?.semanticKind == .batchExecution)
    #expect(executionActivity?.title == "WriteBatch、更新日历")
    #expect(executionActivity?.subtitle == "批量执行 · 文件修改 · 日历")
}

@Test func classifiesCalendarMutationRequestsAndFailures() {
    let call = AgentToolCall(id: "calendar-write", name: "calendar_write", argumentsJSON: "{\"operation\":\"create_event\",\"calendarID\":\"default\"}")
    let failure = AgentToolFailure(runID: "run", sessionID: "session", toolCallID: call.id, toolName: call.name, message: "Invalid arguments: Calendar 'default' was not found")
    let classifier = AgentToolActivityClassifier()

    let requested = classifier.activity(forRequestedCall: call)
    let failed = classifier.activity(forFailure: failure)
    #expect(requested?.semanticKind == .calendar)
    #expect(requested?.title == "日历：新建日程")
    #expect(requested?.target == "default")
    #expect(failed?.semanticKind == .calendar)
    #expect(failed?.phase == .failed)
    #expect(failed?.detail?.contains("Calendar 'default' was not found") == true)
}

@Test func classifiesLegacyCalendarIDsBeforeRegistryNormalization() {
    let classifier = AgentToolActivityClassifier()
    let write = AgentToolCall(
        id: "calendar-write-legacy",
        name: "calendar_write",
        argumentsJSON: #"{"operation":"delete_event","event_id":"event-legacy"}"#
    )
    let read = AgentToolCall(
        id: "calendar-read-legacy",
        name: "calendar_read",
        argumentsJSON: #"{"operation":"list_events","calendar_id":"calendar-legacy"}"#
    )

    #expect(classifier.activity(forRequestedCall: write)?.target == "event-legacy")
    #expect(classifier.activity(forRequestedCall: read)?.target == "calendar-legacy")
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
