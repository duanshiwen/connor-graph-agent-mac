import Foundation

// Continuity preflight enforcement for the model-driven runtime. The Runtime does
// not preload Memory, profile, or Note candidates; these policies require the
// model to complete the continuity reads itself and choose the search keywords.

/// Classifies evidence already gathered for answer-quality checks.
public struct AgentEvidenceValidationPolicy: Sendable, Equatable {
    public static let webEvidenceTools = ["web_search", "web_fetch"]
    public static let memoryEvidenceTools = [
        "memory_os_recent_context",
        "memory_os_knowledge_context",
        "memory_os_get_current_user_profile"
    ]

    /// 记忆搜索工具组：结构化记忆 + 会话原文检索。session_search 归类于记忆搜索，
    /// 但不加入强制启动读取（只在记忆获取结果不足时使用）。
    public static let memorySearchTools = memoryEvidenceTools + ["session_search"]

    public init() {}

    public func isPureMemoryTask(_ prompt: String) -> Bool {
        hasExplicitMemoryIntent(prompt) && !requiresWebResearch(prompt)
    }

    private func hasExplicitMemoryIntent(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let memorySignals = [
            "memory os", "memory_os", "记忆", "回忆", "我之前", "我们之前",
            "我的偏好", "我的习惯", "我的历史", "此前决定", "过去提到",
            "工作总结", "任务总结", "工作回顾", "任务回顾", "本周工作", "这周工作",
            "总结今天", "总结昨天", "回顾今天", "回顾昨天"
        ]
        return memorySignals.contains(where: normalized.contains)
    }

    public func requiresWebResearch(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        let explicitWebSignals = [
            "网页", "网站", "互联网", "联网", "在线搜索", "网上搜索",
            "internet", "online", "web search", "search the web"
        ]
        let searchSignals = [
            "搜索", "搜寻", "查找", "检索", "调研", "查一查", "查一下",
            "search", "find online", "look up", "research"
        ]
        let freshnessOrVerificationSignals = [
            "最新", "目前", "当前版本", "截至", "实时", "新闻", "天气", "价格", "汇率", "股票",
            "验证", "核实", "官方", "外部", "latest", "current version", "up to date", "verify", "official"
        ]
        let localSourceSignals = [
            "本地文件", "文件夹", "目录", "代码库", "仓库", "工作区",
            "local file", "folder", "directory", "repository", "workspace"
        ]
        let hasExplicitWebIntent = explicitWebSignals.contains(where: normalized.contains)
        let hasFreshnessOrVerificationNeed = freshnessOrVerificationSignals.contains(where: normalized.contains)
        let hasSearchIntent = searchSignals.contains(where: normalized.contains)
        let isClearlyLocalSearch = localSourceSignals.contains(where: normalized.contains) && !hasExplicitWebIntent
        return hasExplicitWebIntent || hasFreshnessOrVerificationNeed || (hasSearchIntent && !isClearlyLocalSearch)
    }
}

/// Enforces one leading current-time attempt when the tool is available.
/// Invocation, rather than success, unlocks the rest of the run.
public struct AgentCurrentTimePreflightPolicy: Sendable, Equatable {
    public static let requiredToolName = "get_current_time"

    public init() {}

    public func requiresAttempt(
        availableTools: [AgentToolDefinition],
        didAttempt: Bool
    ) -> Bool {
        !didAttempt && availableTools.contains { $0.name == Self.requiredToolName }
    }

    public func correctionInstruction() -> String {
        """
        Mandatory current-time preflight is incomplete. Before any other tool call or final answer, call `get_current_time`. This is a first-attempt requirement, not a success requirement: if the call returns empty content or fails, preserve the real result, do not retry automatically, and continue with the remaining bootstrap and task. Never replace a failed time result with a guessed current time.
        """
    }
}

/// Enforces one initial Note search when the read-only tool is available.
/// Later focused Note searches remain independent and do not restart preflight.
public struct AgentNoteSearchPreflightPolicy: Sendable, Equatable {
    public static let requiredToolName = "note_search"

    public init() {}

    public func requiresAttempt(
        availableTools: [AgentToolDefinition],
        didAttempt: Bool
    ) -> Bool {
        !didAttempt && availableTools.contains { $0.name == Self.requiredToolName }
    }

    public func correctionInstruction() -> String {
        """
        Mandatory Note preflight is incomplete. Before task-specific tool use or a final answer, include one `note_search` native call inside `parallel_tool_query`, using compact topic terms, entity names, or a subject phrase tied to the latest actual user request. Use an empty `query` only when no meaningful search terms can be formed. This is a one-attempt requirement: a successful empty result or a real failure satisfies the startup attempt. Inspect candidates first; put only selected `note_get` calls into a later `parallel_tool_query` batch alongside any selected Web or other detail reads.
        """
    }
}

/// Requires one Session full-text search when the model already ran the Memory OS
/// continuity searches and their results are insufficient (empty, partial, or lacking
/// the requested detail). Invocation, rather than success, unlocks the rest of the run.
public struct AgentSessionSearchPreflightPolicy: Sendable, Equatable {
    public static let requiredToolName = "session_search"

    public init() {}

    public func requiresAttempt(
        availableTools: [AgentToolDefinition],
        didAttempt: Bool
    ) -> Bool {
        !didAttempt && availableTools.contains { $0.name == Self.requiredToolName }
    }

    public func correctionInstruction() -> String {
        """
        The Memory OS continuity searches' results are insufficient for the current task — empty, partial, or lacking the specific detail the user asked about. Before task-specific tool use or a final answer, include one `session_search` native call inside `parallel_tool_query`, using compact topic terms, entity names, or a subject phrase tied to the latest actual user request. The session full-text index covers raw chat transcripts; use it to check whether the requested topic was ever discussed before. `session_search` belongs to the memory search group and is encouraged whenever memory retrieval results are insufficient, not only when they are empty. This is a one-attempt requirement: a successful empty result or a real failure satisfies the startup attempt; never fabricate a claim that memory or transcripts were searched.
        """
    }
}

/// Enforces startup continuity retrieval and the late full-profile checkpoint.
public struct AgentContinuityPreflightPolicy: Sendable, Equatable {
    public static let currentUserProfileToolName = "memory_os_get_current_user_profile"
    public static let taskContextPurpose = "task_context"
    public static let finalResponsePurpose = "final_response"
    public static let requiredToolNames = AgentEvidenceValidationPolicy.memoryEvidenceTools

    public init() {}

    public func missingToolNames(
        availableTools: [AgentToolDefinition],
        invokedToolNames: Set<String>
    ) -> [String] {
        let availableNames = Set(availableTools.map(\.name))
        return Self.requiredToolNames.filter {
            availableNames.contains($0) && !invokedToolNames.contains($0)
        }
    }

    public func correctionInstruction(for missingToolNames: [String]) -> String? {
        guard !missingToolNames.isEmpty else { return nil }
        let names = missingToolNames.map { "`\($0)`" }.joined(separator: ", ")
        return """
        Mandatory continuity preflight is incomplete. Before task-specific tool use or a final answer, include every still-missing available continuity read in one `parallel_tool_query` batch: \(names). Each `calls` item uses the exact native tool name and native arguments object. Choose compact topic terms for `memory_os_recent_context` and `memory_os_knowledge_context` from the latest actual user request. Call `memory_os_get_current_user_profile` with `purpose: "task_context"` and `pageSize: 500` (read one page of 500 records; continue through `nextPage` only when more profile evidence is genuinely needed). These are independent paginated sources; do not substitute one for another. A successful empty result still counts as a real call. A failed attempt supplies no evidence; preserve its real error and never fabricate memory.
        """
    }

    public func nextRequiredCurrentUserProfilePage(after result: AgentToolResult) -> Int? {
        guard result.toolName == Self.currentUserProfileToolName,
              result.error == nil,
              let payload = result.contentJSON,
              let data = payload.data(using: .utf8),
              let response = try? JSONDecoder().decode(CurrentUserProfilePaginationResponse.self, from: data),
              response.success else {
            return nil
        }
        return response.nextPage
    }

}

/// Enforces the personal-assistant attention check before final synthesis.
public struct AgentFinalAttentionPreflightPolicy: Sendable, Equatable {
    public static let requiredToolNames = [AttentionBriefTool.toolName, "rss_search_items"]

    public init() {}

    public func missingToolNames(
        availableTools: [AgentToolDefinition],
        invokedToolNames: Set<String>
    ) -> [String] {
        let availableNames = Set(availableTools.map(\.name))
        return Self.requiredToolNames.filter {
            availableNames.contains($0) && !invokedToolNames.contains($0)
        }
    }

    public func correctionInstruction(for missingToolNames: [String]) -> String? {
        guard !missingToolNames.isEmpty else { return nil }
        let names = missingToolNames.map { "`\($0)`" }.joined(separator: ", ")
        return """
        Mandatory final attention check is incomplete. Before `prepare_final_output`, put every still-missing available read in one `parallel_tool_query` batch: \(names). Use `attention_brief` with `days: 2`. Use `rss_search_items` with an empty query, the trusted Runtime Context's previous 48-hour ISO-8601 bounds, newest-first sorting, and a small limit. A successful empty result or a real failure satisfies the one-attempt checkpoint. Do not repeat a completed check, do not read full bodies by default, and mention the results only when the user has an immediate action or preparation need.
        """
    }
}

private struct CurrentUserProfilePaginationResponse: Decodable {
    var success: Bool
    var nextPage: Int?
}

public enum AgentModelToolResultReliability: String, Sendable, Equatable {
    case verified
    case unknown
}

public struct AgentModelReliabilityRegistry: Sendable, Equatable {
    public var toolResultReliabilityByModelID: [String: AgentModelToolResultReliability]

    public init(toolResultReliabilityByModelID: [String: AgentModelToolResultReliability] = [:]) {
        self.toolResultReliabilityByModelID = toolResultReliabilityByModelID
    }

    public func toolResultReliability(for modelID: String) -> AgentModelToolResultReliability {
        toolResultReliabilityByModelID[modelID] ?? .unknown
    }
}

public struct AgentExternalResearchAnswerValidator: Sendable, Equatable {
    public init() {}

    public func correctionInstruction(answer: String, evidenceCitations: [String]) -> String? {
        let citations = Array(Set(evidenceCitations)).filter { !$0.isEmpty }
        guard !citations.isEmpty else { return nil }
        guard !citations.contains(where: answer.contains) else { return nil }
        return "External research returned usable page sources, but the draft answer omitted the researched findings and their sources. Re-read the latest actual user request, synthesize the concrete requested result from relevant Web evidence, ignore unrelated memory, and include links only to pages actually used."
    }
}
