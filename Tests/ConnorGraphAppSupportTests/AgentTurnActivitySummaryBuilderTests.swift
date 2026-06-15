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
    #expect(summary.toolNames == ["Glob", "graph_search"])
    #expect(summary.toolCallCount == 2)
    #expect(summary.toolSuccessCount == 2)
    #expect(summary.toolFailureCount == 0)
    #expect(summary.compactToolText == "使用 Glob、graph_search")
    #expect(summary.subtitle == "使用 Glob、graph_search · 6 个底层事件")
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

    #expect(summary.toolNames == ["Read File", "Swift: 编译项目"])
    #expect(summary.compactToolText == "使用 Read File、Swift: 编译项目")
    #expect(summary.subtitle == "使用 Read File、Swift: 编译项目 · 3 个底层事件")
}

@Test func marksTurnFailedWhenAnyToolFails() {
    let process = makeProcess(state: .completed, turnNumber: 3)
    let events: [AgentEventPresentation] = [
        event(kind: "toolRequested", title: "Tool requested: Bash", detail: "Call 1", severity: .info),
        event(kind: "toolFailed", title: "Tool failed: Bash", detail: "Call 1 · command timed out", severity: .error),
        event(kind: "runFailed", title: "Run failed", detail: "command timed out", severity: .error)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .failed)
    #expect(summary.statusText == "已失败")
    #expect(summary.toolNames == ["Bash"])
    #expect(summary.toolFailureCount == 1)
    #expect(summary.primaryErrorMessage == "Call 1 · command timed out")
    #expect(summary.subtitle == "Bash 失败：Call 1 · command timed out · 使用 Bash · 3 个底层事件")
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

    #expect(summary.toolNames == ["Glob", "Bash", "graph_search", "browser_tool"])
    #expect(summary.compactToolText == "使用 Glob、Bash、graph_search 等 4 个工具")
    #expect(summary.subtitle == "使用 Glob、Bash、graph_search 等 4 个工具 · 4 个底层事件")
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
    #expect(summary.subtitle == "正在使用 browser_tool · 2 个底层事件")
}

@Test func marksTurnWaitingForPermissionWhenPermissionIsRequested() {
    let process = makeProcess(state: .running, turnNumber: 11)
    let events: [AgentEventPresentation] = [
        event(kind: "permissionRequested", title: "Permission requested: writeFile", detail: "Tool: write", severity: .warning)
    ]

    let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)

    #expect(summary.state == .waitingForPermission)
    #expect(summary.statusText == "等待确认")
    #expect(summary.hasPermissionRequest)
    #expect(summary.subtitle == "等待权限确认 · 未调用工具 · 1 个底层事件")
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
