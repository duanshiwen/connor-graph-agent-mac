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
    public var requiresFinalAttention: Bool

    public init(
        requiresCurrentTime: Bool,
        requiresContinuity: Bool,
        requiresNoteSearch: Bool,
        requiresFinalProfile: Bool,
        requiresFinalAttention: Bool
    ) {
        self.requiresCurrentTime = requiresCurrentTime
        self.requiresContinuity = requiresContinuity
        self.requiresNoteSearch = requiresNoteSearch
        self.requiresFinalProfile = requiresFinalProfile
        self.requiresFinalAttention = requiresFinalAttention
    }

    public var instruction: String {
        let startup = [
            requiresContinuity
                ? "memory_os_recent_context and memory_os_knowledge_context with compact topic keywords you choose from the latest actual user request, plus memory_os_get_current_user_profile with purpose task_context and pageSize 500, all in one parallel_tool_query batch"
                : nil,
            requiresNoteSearch ? "one initial note_search" : nil
        ].compactMap { $0 }
        let startupText = startup.isEmpty ? "No startup retrieval is required." : "Required startup retrieval: \(startup.joined(separator: ", "))."
        let profileText = requiresFinalProfile
            ? "Before the final answer, complete the full memory_os_get_current_user_profile final_response pagination chain."
            : "Profile reads are model-driven: read one page of 500 records (pageSize 500) in the startup batch, then continue through nextPage only when the task genuinely needs more profile evidence. You may also re-search the profile with compact keywords through the same tool."
        let attentionText = requiresFinalAttention
            ? "The Runtime will complete the final calendar, mail, and RSS attention check before final synthesis; do not call generic attention tools yourself."
            : "No final attention checkpoint is required."
        return """
        ## Runtime Retrieval Plan
        This trusted per-run plan is authoritative for which optional retrieval checkpoints are mandatory. Do not call omitted retrieval tools merely as a generic preflight.
        - \(startupText)
        - \(attentionText)
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
                requiresCurrentTime: false,
                requiresContinuity: true,
                requiresNoteSearch: true,
                requiresFinalProfile: false,
                requiresFinalAttention: true
            )
        }
        return AgentRunRetrievalPlan(
            requiresCurrentTime: false,
            requiresContinuity: true,
            requiresNoteSearch: true,
            requiresFinalProfile: false,
            requiresFinalAttention: true
        )
    }

    public func initiallyExposedTools(
        from definitions: [AgentToolDefinition],
        request: AgentChatRequest,
        mode: AgentToolExposureMode
    ) -> [AgentToolDefinition] {
        let definitions = definitions.filter { $0.name != AgentCurrentTimePreflightPolicy.requiredToolName }
        guard mode == .contextual else { return definitions }
        let context = routingContext(for: request)
        return definitions.filter { definition in
            AssistantToolRouter.interactiveWebDirectToolNames.contains(definition.name)
                || AssistantToolRouter.directToolNames.contains(definition.name)
                    && containsAny(context, signals: Self.localFileSignals)
        }
    }

    private func routingContext(for request: AgentChatRequest) -> String {
        // Direct workspace schemas follow the active instruction only. Historical
        // messages remain available for continuity without expanding the stable surface,
        // except when the user explicitly resumes the immediately preceding task.
        let current = request.userMessage.lowercased()
        guard isExplicitContinuation(current) else { return current }
        let recentTaskContext = request.recentMessages.suffix(6)
            .map(\.content)
            .joined(separator: "\n")
            .lowercased()
        return current + "\n" + recentTaskContext
    }

    private func containsAny(_ text: String, signals: [String]) -> Bool {
        signals.contains(where: text.contains)
    }

    private func isExplicitContinuation(_ text: String) -> Bool {
        Self.continuationSignals.contains { signal in
            text == signal || text.hasPrefix(signal + "，") || text.hasPrefix(signal + ",")
        }
    }

    private static let localFileSignals = ["文件", "目录", "文件夹", "代码", "仓库", "项目", "工作区", "编译", "测试", "重构", "修改", "实现", "file", "folder", "directory", "code", "repo", "project", "workspace", "build", "test", "refactor", "implement", "edit"]
    private static let continuationSignals = [
        "已经选择", "已选择", "继续", "继续执行", "继续制作", "继续制作并发布", "接着做", "接着执行", "好了", "已完成",
        "continue", "continue working", "continue and publish", "resume", "resume work", "done", "selected"
    ]
}

public struct AgentInstructionCapabilityProjector: Sendable, Equatable {
    public init() {}

    public func projectedDocument(
        _ instruction: String,
        availableToolNames: Set<String>
    ) -> AgentPromptDocument {
        let document = AgentPromptModuleCatalog.document(from: instruction)
        let capabilities = AgentPromptCapabilityResolver.capabilities(for: availableToolNames)
        return document.projected(for: capabilities)
    }

    public func project(_ instruction: String, availableToolNames: Set<String>) -> String {
        projectedDocument(instruction, availableToolNames: availableToolNames).renderedText
    }
}
