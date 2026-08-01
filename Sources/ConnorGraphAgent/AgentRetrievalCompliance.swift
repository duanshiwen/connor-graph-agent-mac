import Foundation

/// Classifies evidence already gathered for answer-quality checks.
public struct AgentEvidenceValidationPolicy: Sendable, Equatable {
    public static let webEvidenceTools = ["web_search", "web_fetch", "browser_fetch"]
    public static let memoryEvidenceTools = [
        "memory_os_recent_context",
        "memory_os_knowledge_context",
        "memory_os_get_current_user_profile"
    ]

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
        Mandatory Note preflight is incomplete. Before task-specific tool use or a final answer, include one `note_search` native call inside `parallel_tool_query`, using compact topic keywords, entity names, or a subject phrase tied to the latest actual user request. Use an empty `query` only when no meaningful search terms can be formed. This is a one-attempt requirement: a successful empty result or a real failure satisfies the startup attempt. Inspect candidates first; put only selected `note_get` calls into a later `parallel_tool_query` batch alongside any selected Web or other detail reads.
        """
    }
}

/// Enforces startup continuity retrieval and the late compressed-profile checkpoint.
public struct AgentContinuityPreflightPolicy: Sendable, Equatable {
    public static let currentUserProfileToolName = "memory_os_get_current_user_profile"
    public static let finalResponsePurpose = "final_response"
    public static let requiredToolNames = AgentEvidenceValidationPolicy.memoryEvidenceTools.filter {
        $0 != currentUserProfileToolName
    }

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
        Mandatory continuity preflight is incomplete. Before task-specific tool use or a final answer, include every still-missing available continuity read in one `parallel_tool_query` batch: \(names). Each `calls` item uses the exact native tool name and native arguments object. These are independent paginated sources; do not substitute one for another. A successful empty result still counts as a real call. A failed attempt supplies no evidence; preserve its real error and never fabricate memory. The current-user profile is intentionally excluded from startup continuity and is loaded internally by `prepare_final_output` near finalization.
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

private struct CurrentUserProfilePaginationResponse: Decodable {
    var success: Bool
    var nextPage: Int?
}

public enum AgentMemoryClaimStatus: String, Sendable, Equatable {
    case supported
    case inferred
    case unsupported
    case conflicted
}

public struct AgentMemoryClaimValidation: Sendable, Equatable {
    public var status: AgentMemoryClaimStatus
    public var correctionInstruction: String?
}

public struct AgentMemoryClaimValidator: Sendable, Equatable {
    public init() {}

    public func validate(answer: String, evidencePayloads: [String], citations: [String]) -> AgentMemoryClaimValidation {
        let lower = answer.lowercased()
        let evidence = evidencePayloads.joined(separator: "\n").lowercased()
        let hasAbsoluteClaim = ["确定", "肯定", "一定", "当前是", "就是", "definitely", "certainly", "always"].contains(where: lower.contains)
        if evidence.contains("\"status\":\"conflicted\"") && hasAbsoluteClaim {
            return .init(status: .conflicted, correctionInstruction: "Memory evidence is conflicted. Present the conflicting records and avoid an absolute conclusion.")
        }
        let hasIndirectPath = (2...6).contains { evidence.contains("\"depth\":\($0)") }
        let isQualified = ["可能", "推断", "间接", "may", "might", "inferred", "indirect"].contains(where: lower.contains)
        if hasIndirectPath && !isQualified {
            return .init(status: .inferred, correctionInstruction: "The answer relies on a depth >= 2 indirect path. Lower certainty and label the relationship as indirect or inferred; do not state direct relation or causality.")
        }
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && citations.isEmpty {
            return .init(status: .unsupported, correctionInstruction: "No current-run Memory OS record IDs support the memory answer. Remove unsupported names, entities, dates, numbers, amounts, counts, current-state claims, direct/indirect relations, causality, and absolute assertions, or state that memory did not provide an answer.")
        }
        return .init(status: .supported, correctionInstruction: nil)
    }
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
