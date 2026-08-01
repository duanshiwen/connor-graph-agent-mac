import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func summarizesCompletedTurnWithDeduplicatedTools() {
    let process = makeProcess(state: .completed, turnNumber: 9)
    let events: [AgentEventPresentation] = [
        event(kind: "toolRequested", title: "Tool requested: Glob", detail: "Call 1", severity: .info),
        event(kind: "toolStarted", title: "Tool running: Glob", detail: "Call 1", severity: .info),
        event(kind: "toolFinished", title: "Tool finished: Glob", detail: "Call 1", severity: .success),
        event(kind: "toolRequested", title: "Tool requested: graph_search", detail: "Call 2", severity: .info),
        event(kind: "toolFinished", title: "Tool finished: graph_search", detail: "Call 2", severity: .success),
        event(kind: "runCompleted", title: "Run completed", detail: "Done", severity: .success)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .completed)
    #expect(summary.statusText == "已完成")
    #expect(summary.toolNames == ["查找文件", "搜索知识图谱"])
    #expect(summary.toolCallCount == 2)
    #expect(summary.toolSuccessCount == 2)
    #expect(summary.toolFailureCount == 0)
    #expect(summary.compactToolText == "查找文件、搜索知识图谱")
    #expect(summary.subtitle == "查找文件、搜索知识图谱")
}

@Test func summarizesToolActivitiesWithCraftStyleNames() {
    let process = makeProcess(state: .completed, turnNumber: 12)
    let readActivity = AgentToolActivityPresentation(
        callID: "read-1",
        phase: .requested,
        rawToolName: "Read",
        semanticKind: .readFile,
        title: "Read File",
        target: "AgentChatActivityViews.swift",
        icon: "doc.text.magnifyingglass",
        severity: .info
    )
    let swiftActivity = AgentToolActivityPresentation(
        callID: "bash-1",
        phase: .requested,
        rawToolName: "Bash",
        semanticKind: .swiftBuild,
        title: "Swift: 编译项目",
        target: "swift build",
        icon: "swift",
        severity: .info
    )
    let events: [AgentEventPresentation] = [
        AgentEventPresentation(kind: "toolRequested", title: "Tool requested: Read", detail: "Call 1", severity: .info, runID: "run", sessionID: "session", toolActivity: readActivity),
        AgentEventPresentation(kind: "toolRequested", title: "Tool requested: Bash", detail: "Call 2", severity: .info, runID: "run", sessionID: "session", toolActivity: swiftActivity),
        event(kind: "runCompleted", title: "Run completed", detail: "Done", severity: .success)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.toolNames == ["读取文件", "编译 Swift 项目"])
    #expect(summary.compactToolText == "读取文件、编译 Swift 项目")
    #expect(summary.subtitle == "读取文件、编译 Swift 项目")
}

@Test func keepsRunningTurnWhenOneToolFailsButRunContinues() {
    let process = makeProcess(state: .running, turnNumber: 3)
    let events: [AgentEventPresentation] = [
        event(kind: "toolRequested", title: "Tool requested: Read", detail: "Call 1", severity: .info),
        event(kind: "toolFailed", title: "Tool failed: Read", detail: "Call 1 · file not found", severity: .error),
        event(kind: "toolRequested", title: "Tool requested: Bash", detail: "Call 2", severity: .info),
        event(kind: "toolFinished", title: "Tool finished: Bash", detail: "ok", severity: .success)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .running)
    #expect(summary.statusText == "正在处理")
    #expect(summary.toolNames == ["读取文件", "执行终端命令"])
    #expect(summary.toolFailureCount == 1)
    #expect(summary.primaryErrorMessage == "Call 1 · file not found")
    #expect(summary.subtitle == "正在执行：读取文件、执行终端命令")
}

@Test func marksTurnFailedOnlyWhenRunFails() {
    let process = makeProcess(state: .completed, turnNumber: 13)
    let events: [AgentEventPresentation] = [
        event(kind: "toolRequested", title: "Tool requested: Bash", detail: "Call 1", severity: .info),
        event(kind: "toolFailed", title: "Tool failed: Bash", detail: "Call 1 · command timed out", severity: .error),
        event(kind: "runFailed", title: "Run failed", detail: "command timed out", severity: .error)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .failed)
    #expect(summary.statusText == "已失败")
    #expect(summary.toolNames == ["执行终端命令"])
    #expect(summary.toolFailureCount == 1)
    #expect(summary.primaryErrorMessage == "Call 1 · command timed out")
    #expect(summary.subtitle == "执行终端命令失败：Call 1 · command timed out · 执行终端命令")
}

@Test func marksExplicitlyCancelledRunAsCancelledInsteadOfFailed() {
    let process = makeProcess(state: .cancelled, turnNumber: 14)
    let events = [
        event(kind: "runFailed", title: "Run cancelled", detail: "cancelled by user", severity: .warning)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .cancelled)
    #expect(summary.statusText == "已取消")
    #expect(summary.subtitle == "运行已取消 · 未调用工具")
}

@Test func marksOpenTurnFailedFromExplicitProcessState() {
    let process = makeProcess(state: .failed, turnNumber: 15)

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: [])

    #expect(summary.state == .failed)
    #expect(summary.statusText == "已失败")
}

@Test func summarizesManyToolsWithCompactText() {
    let process = makeProcess(state: .completed, turnNumber: 4)
    let events: [AgentEventPresentation] = [
        event(kind: "toolFinished", title: "Tool finished: Glob", detail: "ok", severity: .success),
        event(kind: "toolFinished", title: "Tool finished: Bash", detail: "ok", severity: .success),
        event(kind: "toolFinished", title: "Tool finished: graph_search", detail: "ok", severity: .success),
        event(kind: "toolFinished", title: "Tool finished: browser_tool", detail: "ok", severity: .success)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.toolNames == ["查找文件", "执行终端命令", "搜索知识图谱", "执行网页操作"])
    #expect(summary.compactToolText == "查找文件、执行终端命令、搜索知识图谱等 4 项操作")
    #expect(summary.subtitle == "查找文件、执行终端命令、搜索知识图谱等 4 项操作")
}

@Test func marksRunningTurnFromProcessState() {
    let process = makeProcess(state: .running, turnNumber: 10)
    let events: [AgentEventPresentation] = [
        event(kind: "toolRequested", title: "Tool requested: browser_tool", detail: "Call 1", severity: .info),
        event(kind: "toolStarted", title: "Tool running: browser_tool", detail: "Call 1", severity: .info)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .running)
    #expect(summary.statusText == "正在处理")
    #expect(summary.title == "第 10 轮 · 正在处理")
    #expect(summary.subtitle == "正在执行：执行网页操作")
}

@Test func marksTurnWaitingForPermissionWhenPermissionIsRequested() {
    let process = makeProcess(state: .running, turnNumber: 11)
    let events: [AgentEventPresentation] = [
        event(kind: "permissionRequested", title: "Permission requested: writeFile", detail: "Tool: write", severity: .warning)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .waitingForPermission)
    #expect(summary.statusText == "请求审批")
    #expect(summary.hasPermissionRequest)
    #expect(summary.subtitle == "当前会话正在等待权限审批，请前往处理 · 未调用工具")
}

@Test func clearsWaitingStateAfterPermissionIsApproved() {
    let process = makeProcess(state: .running, turnNumber: 12)
    let events: [AgentEventPresentation] = [
        event(kind: "permissionRequested", title: "Permission requested: workspaceWrite", detail: "Request permission-1", severity: .warning),
        event(kind: "permissionResolved", title: "Permission approved: workspaceWrite", detail: "Request permission-1", severity: .success)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.hasPermissionRequest)
    #expect(!summary.isWaitingForPermission)
    #expect(summary.state == .running)
    #expect(summary.statusText == "正在处理")
    #expect(summary.subtitle == "未调用工具")
}

@Test func localizesRegisteredToolFamiliesAndFutureToolFallbacks() {
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "note_search", semanticKind: .unknown) == "搜索笔记")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "note_get", semanticKind: .unknown) == "读取笔记详情")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "mail_send_draft", semanticKind: .unknown) == "发送邮件")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "rss_sync_source", semanticKind: .unknown) == "同步 RSS 订阅源")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "memory_os_l4_neighbors", semanticKind: .unknown) == "查看实体关系")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "cloud_kb_future_operation", semanticKind: .unknown) == "cloud_kb_future_operation")
    #expect(AgentToolDisplayNameResolver.displayName(rawToolName: "mcp__lark__search", semanticKind: .unknown) == "mcp__lark__search")
    #expect(AgentToolDisplayNameResolver.categoryName(rawToolName: "mcp__lark__search", semanticKind: .mcp) == "MCP")
    #expect(AgentToolDisplayNameResolver.categoryName(rawToolName: "cloud_kb_future_operation", semanticKind: .unknown) == "知识库")
    #expect(AgentToolDisplayNameResolver.categoryName(rawToolName: "parallel_tool_query", semanticKind: .parallelQuery) == "并行查询")
}

@Test func toolSummaryCountsInvocationsInsteadOfLifecycleEvents() {
    let summary = AgentTurnActivitySummaryBuilder().summary(
        process: makeProcess(state: .completed, turnNumber: 14),
        events: [
            event(kind: "toolRequested", title: "Tool requested: get_current_time", detail: "Call 1", severity: .info),
            event(kind: "toolStarted", title: "Tool running: get_current_time", detail: "Call 1", severity: .info),
            event(kind: "toolFinished", title: "Tool finished: get_current_time", detail: "Call 1", severity: .success)
        ]
    )

    #expect(summary.toolSummaries.first?.compactCountText == "获取当前时间")
}

@Test func showsCompactionOnlyWhileLifecycleIsActive() {
    let process = makeProcess(state: .running, turnNumber: 15)
    let started = event(
        kind: "compactionStarted",
        title: "正在压缩上下文",
        detail: "generation 1",
        severity: .info
    )
    let completed = event(
        kind: "compactionCompleted",
        title: "上下文压缩完成",
        detail: "80000 -> 45000 tokens",
        severity: .success
    )

    let active = AgentTurnActivitySummaryBuilder().summary(process: process, events: [started])
    let hidden = AgentTurnActivitySummaryBuilder().summary(process: process, events: [started, completed])

    #expect(active.statusText == "正在压缩上下文")
    #expect(active.state == .running)
    #expect(hidden.statusText == "正在处理")
}

private func makeProcess(state: AgentChatTurnProcessState, turnNumber: Int) -> AgentChatTurnProcessPresentation {
    let user = AgentMessage(id: "user-\(turnNumber)", role: .user, content: "测试请求", createdAt: Date(timeIntervalSince1970: 0))
    let pending = AgentChatPendingAssistantPresentation(messages: [user])
    var process = AgentChatTurnProcessPresentation(
        pending: pending,
        conversationHistory: AgentChatMessagePresentation.rows(messages: [user], lastContext: nil),
        state: state
    )
    process.id = "process-\(turnNumber)"
    process.turnNumber = turnNumber
    return process
}

private func event(kind: String, title: String, detail: String, severity: AgentEventPresentationSeverity) -> AgentEventPresentation {
    AgentEventPresentation(kind: kind, title: title, detail: detail, severity: severity, runID: "run", sessionID: "session")
}
