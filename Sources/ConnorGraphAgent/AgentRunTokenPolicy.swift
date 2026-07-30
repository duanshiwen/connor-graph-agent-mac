import Foundation

public enum AgentPreflightMode: String, Codable, Sendable, Equatable {
    case always
    case contextual
}

public enum AgentToolExposureMode: String, Codable, Sendable, Equatable {
    case all
    case contextual
}

public struct AgentRunRetrievalPlan: Sendable, Equatable {
    public var requiresCurrentTime: Bool
    public var requiresContinuity: Bool
    public var requiresNoteSearch: Bool
    public var requiresFinalProfile: Bool

    public init(
        requiresCurrentTime: Bool,
        requiresContinuity: Bool,
        requiresNoteSearch: Bool,
        requiresFinalProfile: Bool
    ) {
        self.requiresCurrentTime = requiresCurrentTime
        self.requiresContinuity = requiresContinuity
        self.requiresNoteSearch = requiresNoteSearch
        self.requiresFinalProfile = requiresFinalProfile
    }

    public var instruction: String {
        let startup = [
            requiresCurrentTime ? "get_current_time first" : nil,
            requiresContinuity ? "memory_os_recent_context and memory_os_knowledge_context" : nil,
            requiresNoteSearch ? "one initial note_search" : nil
        ].compactMap { $0 }
        let startupText = startup.isEmpty ? "No startup retrieval is required." : "Required startup retrieval: \(startup.joined(separator: ", "))."
        let profileText = requiresFinalProfile
            ? "Before the final answer, complete the compressed memory_os_get_current_user_profile final_response pagination chain."
            : "No final-response profile checkpoint is required unless this run successfully updates the current-user profile."
        return """
        ## Runtime Retrieval Plan
        This trusted per-run plan is authoritative for which optional retrieval checkpoints are mandatory. Do not call omitted retrieval tools merely as a generic preflight.
        - \(startupText)
        - \(profileText)
        """
    }
}

public struct AgentRunTokenPolicy: Sendable, Equatable {
    public init() {}

    public func retrievalPlan(
        for request: AgentChatRequest,
        mode: AgentPreflightMode
    ) -> AgentRunRetrievalPlan {
        guard mode == .contextual else {
            return AgentRunRetrievalPlan(
                requiresCurrentTime: true,
                requiresContinuity: true,
                requiresNoteSearch: true,
                requiresFinalProfile: true
            )
        }

        let context = routingContext(for: request)
        let timeRelevant = containsAny(context, signals: Self.timeSignals)
        let memoryRelevant = containsAny(context, signals: Self.memorySignals)
        let noteRelevant = containsAny(context, signals: Self.noteSignals)
        let profileRelevant = memoryRelevant || containsAny(context, signals: Self.profileSignals)
        return AgentRunRetrievalPlan(
            requiresCurrentTime: timeRelevant,
            requiresContinuity: memoryRelevant,
            requiresNoteSearch: noteRelevant,
            requiresFinalProfile: profileRelevant
        )
    }

    public func exposedTools(
        from definitions: [AgentToolDefinition],
        request: AgentChatRequest,
        retrievalPlan: AgentRunRetrievalPlan,
        mode: AgentToolExposureMode
    ) -> [AgentToolDefinition] {
        guard mode == .contextual else { return definitions }
        let context = routingContext(for: request)
        return definitions.filter { definition in
            shouldExpose(definition.name, context: context, request: request, retrievalPlan: retrievalPlan)
        }
    }

    private func shouldExpose(
        _ name: String,
        context: String,
        request: AgentChatRequest,
        retrievalPlan: AgentRunRetrievalPlan
    ) -> Bool {
        if name == AgentCurrentTimePreflightPolicy.requiredToolName { return retrievalPlan.requiresCurrentTime }
        if AgentContinuityPreflightPolicy.requiredToolNames.contains(name) { return retrievalPlan.requiresContinuity }
        if name == AgentNoteSearchPreflightPolicy.requiredToolName { return retrievalPlan.requiresNoteSearch }
        if name == AgentContinuityPreflightPolicy.currentUserProfileToolName { return retrievalPlan.requiresFinalProfile }
        if name == "load_attachment_context" { return !request.attachmentRefs.isEmpty || !request.attachmentContextPlan.isEmpty }

        if Self.localToolNames.contains(name) || matches(name, prefixes: ["local_", "workspace_"]) { return containsAny(context, signals: Self.localFileSignals) }
        if matches(name, prefixes: ["calendar_"]) { return containsAny(context, signals: Self.calendarSignals) }
        if matches(name, prefixes: ["mail_"]) { return containsAny(context, signals: Self.mailSignals) }
        if matches(name, prefixes: ["rss_"]) { return containsAny(context, signals: Self.rssSignals) }
        if matches(name, prefixes: ["browser_", "web_"]) { return containsAny(context, signals: Self.webSignals) }
        if matches(name, prefixes: ["contact", "person_"]) { return containsAny(context, signals: Self.contactSignals) }
        if matches(name, prefixes: ["science_", "time_analy"]) { return containsAny(context, signals: Self.scienceSignals) }
        if matches(name, prefixes: ["task_", "tasks_"]) { return containsAny(context, signals: Self.taskSignals) }
        if matches(name, prefixes: ["connor_skill_"]) { return containsAny(context, signals: Self.skillSignals) }
        if matches(name, prefixes: ["personality_"]) { return containsAny(context, signals: Self.personalitySignals) }
        if matches(name, prefixes: ["note_"]) { return containsAny(context, signals: Self.noteSignals) }
        if matches(name, prefixes: ["memory_os_"]) { return containsAny(context, signals: Self.memorySignals) }
        if matches(name, prefixes: ["generate_image", "edit_image", "image_search", "present_image"]) { return containsAny(context, signals: Self.imageSignals) }
        if name == "get_current_environment" || matches(name, prefixes: ["environment_"]) { return containsAny(context, signals: Self.environmentSignals) }
        if name == ShareProgressUpdateTool.toolName { return containsAny(context, signals: Self.multiStepSignals) }
        if matches(name, prefixes: ["session_"]) { return containsAny(context, signals: Self.sessionSignals) }
        if matches(name, prefixes: ["cloud_kb_"]) { return containsAny(context, signals: Self.memorySignals + Self.webSignals) }
        if name == "graph_search" { return containsAny(context, signals: Self.memorySignals + Self.contactSignals) }

        // Preserve externally supplied and future tools until they declare a routing family.
        return true
    }

    private func routingContext(for request: AgentChatRequest) -> String {
        ([request.userMessage] + request.recentMessages.suffix(4).map(\.content))
            .joined(separator: "\n")
            .lowercased()
    }

    private func containsAny(_ text: String, signals: [String]) -> Bool {
        signals.contains(where: text.contains)
    }

    private func matches(_ name: String, prefixes: [String]) -> Bool {
        prefixes.contains(where: name.hasPrefix)
    }

    private static let timeSignals = ["今天", "明天", "昨天", "现在", "当前", "最近", "最新", "时间", "日期", "截止", "日程", "天气", "today", "tomorrow", "yesterday", "current", "latest", "time", "date", "deadline", "calendar", "weather"]
    private static let memorySignals = ["记忆", "回忆", "之前", "以前", "过去", "偏好", "习惯", "我们讨论", "我说过", "memory", "remember", "previously", "before", "preference", "history"]
    private static let noteSignals = ["笔记", "便签", "备忘", "note", "notes", "notebook"]
    private static let profileSignals = ["按我的", "适合我", "为我推荐", "个性化", "我的风格", "my style", "for me", "personalized", "recommend"]
    private static let localFileSignals = ["文件", "目录", "文件夹", "代码", "仓库", "项目", "工作区", "编译", "测试", "重构", "修改", "实现", "file", "folder", "directory", "code", "repo", "project", "workspace", "build", "test", "refactor", "implement", "edit"]
    private static let calendarSignals = timeSignals + ["会议", "行程", "安排", "预约", "event", "meeting", "schedule", "appointment"]
    private static let mailSignals = ["邮件", "邮箱", "收件箱", "email", "mail", "inbox"]
    private static let rssSignals = ["rss", "订阅", "信息源", "feed"]
    private static let webSignals = ["网页", "网站", "联网", "上网", "搜索", "查资料", "核实", "官方资料", "web", "website", "online", "search", "research", "verify", "latest"]
    private static let contactSignals = ["联系人", "通讯录", "某人", "同事", "朋友", "contact", "person", "people", "colleague", "friend"]
    private static let scienceSignals = ["计算", "统计", "公式", "矩阵", "单位", "方程", "优化", "compute", "statistics", "formula", "matrix", "units", "equation"]
    private static let taskSignals = ["任务", "待办", "清单", "todo", "task", "checklist"]
    private static let skillSignals = ["技能", "skill", "工作流", "workflow"]
    private static let personalitySignals = ["人格", "性格", "语气", "以后都", "personality", "tone", "from now on"]
    private static let imageSignals = ["图片", "图像", "照片", "配图", "生成图", "改图", "image", "photo", "picture", "illustration"]
    private static let environmentSignals = ["天气", "位置", "地点", "气温", "下雨", "weather", "location", "temperature", "rain"]
    private static let multiStepSignals = ["系统地", "完整", "全面", "逐步", "多步骤", "重构", "实现", "调研", "systematically", "comprehensive", "multi-step", "multi step", "step by step", "refactor", "implement", "research"]
    private static let sessionSignals = ["会话状态", "停止", "取消", "继续运行", "session status", "cancel", "stop", "continue"]
    fileprivate static let localToolNames: Set<String> = ["Read", "LS", "Glob", "Grep", "Write", "Edit", "MultiEdit", "Bash"]
}

public struct AgentInstructionCapabilityProjector: Sendable, Equatable {
    public init() {}

    public func project(_ instruction: String, availableToolNames: Set<String>) -> String {
        let hasCurrentTime = availableToolNames.contains(AgentCurrentTimePreflightPolicy.requiredToolName)
        let hasMemory = availableToolNames.contains(where: { $0.hasPrefix("memory_os_") })
        let hasNote = availableToolNames.contains(where: { $0.hasPrefix("note_") })
        let hasSkills = availableToolNames.contains(where: { $0.hasPrefix("connor_skill_") })
        let hasPeople = availableToolNames.contains(where: { $0.hasPrefix("contact") || $0.hasPrefix("person_") })
        let hasCalendar = availableToolNames.contains(where: { $0.hasPrefix("calendar_") })
        let hasMail = availableToolNames.contains(where: { $0.hasPrefix("mail_") })
        let hasRSS = availableToolNames.contains(where: { $0.hasPrefix("rss_") })
        let hasBrowserHistory = availableToolNames.contains(where: { $0.hasPrefix("browser_history_") })
        let hasNativeSources = hasCalendar || hasMail || hasRSS || hasBrowserHistory
        let hasCloudKnowledge = availableToolNames.contains(where: { $0.hasPrefix("cloud_kb_") })
        let hasWeb = availableToolNames.contains(where: { $0.hasPrefix("web_") || $0 == "browser_fetch" })
        let hasImages = availableToolNames.contains(where: { ["generate_image", "edit_image", "image_search", "present_image"].contains($0) })
        let hasWorkspaceTools = availableToolNames.contains(where: {
            AgentRunTokenPolicy.localToolNames.contains($0)
                || $0.hasPrefix("local_")
                || $0.hasPrefix("workspace_")
        })
        let omittedHeadings = Set([
            hasWorkspaceTools ? nil : "Programming and Precision Work",
            hasCurrentTime ? nil : "Current Time Retrieval Rules",
            hasMemory ? nil : "Memory OS Architecture",
            hasMemory ? nil : "Memory Retrieval Rules",
            hasMemory ? nil : "Personal Continuity and Tailoring",
            hasNote ? nil : "Note Reference Materials",
            hasNote ? nil : "Note Retrieval Rules",
            hasSkills ? nil : "Skill Discovery Rules",
            hasSkills ? nil : "Connor Skill Tools",
            hasPeople ? nil : "Person Registry and Relationships",
            hasCalendar ? nil : "Calendar Retrieval Rules",
            hasCalendar ? nil : "Calendar Tool Workflow",
            hasMail ? nil : "Mail Retrieval Rules",
            hasMail ? nil : "Mail Tool Workflow",
            hasRSS ? nil : "RSS Tool Workflow",
            hasBrowserHistory ? nil : "Browser History Tool Workflow",
            hasNativeSources ? nil : "Native Personal Source Tools",
            hasNativeSources ? nil : "Native Source Evidence Rules",
            hasCloudKnowledge ? nil : "Cloud Knowledge Retrieval Rules",
            hasWeb ? nil : "Web Research Rules",
            hasImages ? nil : "Rich Media Responses"
        ].compactMap { $0 })
        guard !omittedHeadings.isEmpty else { return instruction }

        var output: [String] = []
        var omitting = false
        for line in instruction.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                omitting = omittedHeadings.contains(String(line.dropFirst(3)))
            }
            if !omitting { output.append(line) }
        }
        return output.joined(separator: "\n")
    }
}
