import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct ConnorPersonalitySnapshot: Codable, Sendable, Equatable {
    public var personality: ConnorPersonalitySettings
    public var revision: Int

    public init(personality: ConnorPersonalitySettings, revision: Int) {
        self.personality = personality
        self.revision = revision
    }
}

public enum ConnorPersonalityUpdateMode: String, Codable, Sendable, Equatable, CaseIterable {
    case merge
    case replace
    case reset
}

public struct ConnorPersonalityProposal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var mode: ConnorPersonalityUpdateMode
    public var request: String
    public var before: ConnorPersonalitySettings
    public var after: ConnorPersonalitySettings
    public var expectedRevision: Int
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: String = UUID().uuidString,
        mode: ConnorPersonalityUpdateMode,
        request: String,
        before: ConnorPersonalitySettings,
        after: ConnorPersonalitySettings,
        expectedRevision: Int,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.mode = mode
        self.request = request
        self.before = before
        self.after = after
        self.expectedRevision = expectedRevision
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(30 * 60)
    }
}

public enum ConnorPersonalityProposalError: Error, Sendable, Equatable, LocalizedError {
    case invalidMode(String)
    case requestRequired
    case requestTooLong
    case explicitPersistentRequestRequired
    case nameChangeForbidden
    case revisionConflict(expected: Int, actual: Int)
    case proposalNotFound
    case proposalExpired
    case proposalAlreadyCommitted

    public var errorDescription: String? {
        switch self {
        case .invalidMode(let mode): "不支持的人格修改模式：\(mode)。"
        case .requestRequired: "merge 和 replace 模式必须提供人格修改要求。"
        case .requestTooLong: "人格修改要求过长，请缩短到 2000 字以内。"
        case .explicitPersistentRequestRequired: "本轮用户只是在询问人格属性，没有明确要求持久修改人格。"
        case .nameChangeForbidden: "康纳同学的姓名不可修改、替换、缩写或设置别名。"
        case .revisionConflict(let expected, let actual): "人格配置已发生变化（提议版本 \(expected)，当前版本 \(actual)），请重新读取并生成提议。"
        case .proposalNotFound: "人格变更提议不存在，请重新生成。"
        case .proposalExpired: "人格变更提议已过期，请重新生成。"
        case .proposalAlreadyCommitted: "人格变更提议已经提交，不能重复应用。"
        }
    }
}

public struct ConnorPersonalityRuntime: Sendable {
    public var snapshot: @Sendable () async throws -> ConnorPersonalitySnapshot
    public var commit: @Sendable (ConnorPersonalityProposal) async throws -> ConnorPersonalitySnapshot

    public init(
        snapshot: @escaping @Sendable () async throws -> ConnorPersonalitySnapshot,
        commit: @escaping @Sendable (ConnorPersonalityProposal) async throws -> ConnorPersonalitySnapshot
    ) {
        self.snapshot = snapshot
        self.commit = commit
    }
}

public enum ConnorPersonalitySafetyPolicy {
    public static func validatePersistentMutationIntent(_ userPrompt: String) throws {
        let compact = userPrompt.lowercased().replacingOccurrences(of: " ", with: "")
        let mutationSignals = [
            "以后", "今后", "从现在开始", "一直", "永久", "设为", "设置为", "设置成", "改为", "改成",
            "调成", "调整为", "调整成", "变为", "变成", "调整人格", "调整性格", "修改人格", "修改性格",
            "更新人格", "更新性格", "恢复默认性格", "恢复默认人格",
            "fromnowon", "always", "setyour", "changeyour", "updateyourpersonality", "resetyourpersonality"
        ]
        let questionSignals = [
            "你是", "你属于", "你的性别", "什么性别", "男生还是女生", "男性还是女性", "是什么", "吗", "呢", "?", "？",
            "areyou", "whatisyour", "whichgender"
        ]
        let personalityTargets = ["人格", "性格", "沟通风格", "说话风格", "语气", "personality", "communicationstyle", "tone"]
        let changeRequests = ["能不能", "可不可以", "可以把", "请把", "麻烦把", "couldyou", "canyou", "please"]
        let desiredDirections = ["更", "再", "一点", "more", "less"]
        let hasMutationIntent = mutationSignals.contains(where: compact.contains)
            || (personalityTargets.contains(where: compact.contains)
                && changeRequests.contains(where: compact.contains)
                && desiredDirections.contains(where: compact.contains))
        if questionSignals.contains(where: compact.contains),
           !hasMutationIntent {
            throw ConnorPersonalityProposalError.explicitPersistentRequestRequired
        }
    }

    public static func validateRequest(_ request: String) throws {
        let compact = request.lowercased().replacingOccurrences(of: " ", with: "")
        let nameChangeSignals = [
            "把你改名", "将你改名", "给你改名", "名字改成", "更名为", "以后叫你", "你改叫",
            "你叫做", "你叫成", "你的别名", "renameyou", "callyourself", "yournameis", "giveyouanalias"
        ]
        if nameChangeSignals.contains(where: compact.contains) {
            throw ConnorPersonalityProposalError.nameChangeForbidden
        }
    }
}

public actor ConnorPersonalityProposalStore {
    private var proposals: [String: ConnorPersonalityProposal] = [:]
    private var committedIDs: Set<String> = []

    public init() {}

    public func insert(_ proposal: ConnorPersonalityProposal) {
        proposals[proposal.id] = proposal
    }

    public func proposal(id: String, now: Date = Date()) throws -> ConnorPersonalityProposal {
        guard !committedIDs.contains(id) else { throw ConnorPersonalityProposalError.proposalAlreadyCommitted }
        guard let proposal = proposals[id] else { throw ConnorPersonalityProposalError.proposalNotFound }
        guard proposal.expiresAt > now else {
            proposals[id] = nil
            throw ConnorPersonalityProposalError.proposalExpired
        }
        return proposal
    }

    public func markCommitted(id: String) {
        proposals[id] = nil
        committedIDs.insert(id)
    }
}

public struct ConnorPersonalityGetCurrentTool: AgentTool {
    public let name = "personality_get_current"
    public let description = "Read the current confirmed personality for 康纳同学 and its revision. The fixed name cannot be changed. Call this before proposing a persistent personality update."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [:], required: [])
    private let runtime: ConnorPersonalityRuntime

    public init(runtime: ConnorPersonalityRuntime) { self.runtime = runtime }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let snapshot = try await runtime.snapshot()
        let payload = ConnorPersonalityCurrentPayload(
            lockedName: ConnorPersonalitySettings.lockedDisplayName,
            revision: snapshot.revision,
            personality: snapshot.personality
        )
        return try personalityToolResult(payload, text: "当前人格配置版本为 \(snapshot.revision)，固定姓名为康纳同学。", toolName: name, context: context)
    }
}

public struct ConnorPersonalityProposeUpdateTool: AgentTool {
    public let name = "personality_propose_update"
    public let description = "Generate a governed personality-change proposal for 康纳同学. This never saves settings. Use only when the latest user message explicitly requests a persistent change. Questions about current attributes, including gender, are read-only and must never call this tool. Temporary tone requests should be followed only for the current response. Name changes are forbidden."
    public let permission: AgentPermissionCapability = .modelCall
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "request": .string(description: "User's persistent personality request. Required for merge and replace; omit for reset."),
        "mode": .stringEnumeration(values: ConnorPersonalityUpdateMode.allCases.map(\.rawValue), description: "Update mode."),
        "expectedRevision": .integer(description: "Exact revision returned by personality_get_current.")
    ], required: ["mode", "expectedRevision"])

    private let runtime: ConnorPersonalityRuntime
    private let provider: AnyAgentModelProvider
    private let store: ConnorPersonalityProposalStore

    public init(runtime: ConnorPersonalityRuntime, provider: AnyAgentModelProvider, store: ConnorPersonalityProposalStore) {
        self.runtime = runtime
        self.provider = provider
        self.store = store
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(context.userPrompt)
        let modeRaw = arguments.string("mode")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let mode = ConnorPersonalityUpdateMode(rawValue: modeRaw) else {
            throw ConnorPersonalityProposalError.invalidMode(modeRaw)
        }
        guard let expectedRevision = arguments.int("expectedRevision") ?? arguments.int("expected_revision") else {
            throw AgentToolError.invalidArguments("expectedRevision is required")
        }
        let request = arguments.string("request")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if mode != .reset, request.isEmpty { throw ConnorPersonalityProposalError.requestRequired }
        if request.count > 2_000 { throw ConnorPersonalityProposalError.requestTooLong }
        try ConnorPersonalitySafetyPolicy.validateRequest(request)

        let current = try await runtime.snapshot()
        guard expectedRevision == current.revision else {
            throw ConnorPersonalityProposalError.revisionConflict(expected: expectedRevision, actual: current.revision)
        }
        let after: ConnorPersonalitySettings
        if mode == .reset {
            after = .empty
        } else {
            after = try await ConnorPersonalityGenerator().generateUpdate(
                from: request,
                mode: mode,
                current: current.personality,
                provider: provider
            )
        }
        let proposal = ConnorPersonalityProposal(
            mode: mode,
            request: request,
            before: current.personality,
            after: after,
            expectedRevision: current.revision
        )
        await store.insert(proposal)
        let payload = ConnorPersonalityProposalPayload(
            proposalID: proposal.id,
            lockedName: ConnorPersonalitySettings.lockedDisplayName,
            mode: mode,
            expectedRevision: proposal.expectedRevision,
            expiresAt: proposal.expiresAt,
            before: proposal.before,
            after: proposal.after,
            requiresExplicitApproval: false
        )
        return try personalityToolResult(
            payload,
            text: "已生成未保存的人格变更提议 \(proposal.id)。请立即调用 personality_commit_proposal 直接应用。",
            toolName: name,
            context: context
        )
    }
}

/// One-step session tool. Proposal generation and durable commit deliberately share
/// one invocation so a runtime rebuild cannot orphan an in-memory proposal ID.
public struct ConnorPersonalityUpdateTool: AgentTool {
    public let name = "personality_update"
    public let description = "Generate, validate, and durably apply a persistent personality update for 康纳同学 in one call. Use only when the latest user message explicitly asks for a lasting change. This call does not require a second confirmation in ask-to-write mode; read-only sessions reject it."
    public let permission: AgentPermissionCapability = .mutatePersonality
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "request": .string(description: "User's persistent personality request. Use an empty string only for reset."),
        "mode": .stringEnumeration(
            values: ConnorPersonalityUpdateMode.allCases.map(\.rawValue),
            description: "Update mode: merge preserves current fields not changed by the request; replace generates a complete replacement; reset restores the default personality and requires an empty request."
        ),
        "expectedRevision": .integer(description: "Exact revision returned by personality_get_current.")
    ], required: ["request", "mode", "expectedRevision"])

    private let runtime: ConnorPersonalityRuntime
    private let provider: AnyAgentModelProvider

    public init(runtime: ConnorPersonalityRuntime, provider: AnyAgentModelProvider) {
        self.runtime = runtime
        self.provider = provider
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(context.userPrompt)
        let modeRaw = arguments.string("mode")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let mode = ConnorPersonalityUpdateMode(rawValue: modeRaw) else {
            throw ConnorPersonalityProposalError.invalidMode(modeRaw)
        }
        guard let expectedRevision = arguments.int("expectedRevision") ?? arguments.int("expected_revision") else {
            throw AgentToolError.invalidArguments("expectedRevision is required")
        }
        let request = arguments.string("request")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if mode != .reset, request.isEmpty { throw ConnorPersonalityProposalError.requestRequired }
        if request.count > 2_000 { throw ConnorPersonalityProposalError.requestTooLong }
        try ConnorPersonalitySafetyPolicy.validateRequest(request)

        let current = try await runtime.snapshot()
        guard current.revision == expectedRevision else {
            throw ConnorPersonalityProposalError.revisionConflict(expected: expectedRevision, actual: current.revision)
        }
        let after: ConnorPersonalitySettings
        if mode == .reset {
            after = .empty
        } else {
            after = try await ConnorPersonalityGenerator().generateUpdate(
                from: request,
                mode: mode,
                current: current.personality,
                provider: provider
            )
        }
        let proposal = ConnorPersonalityProposal(
            mode: mode,
            request: request,
            before: current.personality,
            after: after,
            expectedRevision: expectedRevision
        )
        let updated = try await runtime.commit(proposal)
        let payload = ConnorPersonalityCommitPayload(
            proposalID: proposal.id,
            lockedName: ConnorPersonalitySettings.lockedDisplayName,
            revision: updated.revision,
            personality: updated.personality
        )
        return try personalityToolResult(
            payload,
            text: "人格配置已保存为版本 \(updated.revision)，将在后续对话中生效。康纳同学的姓名保持不变。",
            toolName: name,
            context: context
        )
    }
}

public struct ConnorPersonalityCommitProposalTool: AgentTool {
    public let name = "personality_commit_proposal"
    public let description = "Immediately commit an existing personality proposal only when the latest user message explicitly requests a persistent change, without a second confirmation or native approval step. Never commit in response to a question about current attributes, including gender, even if an older proposal ID appears in conversation history. Pass only the proposal ID returned by personality_propose_update. Read-only sessions still reject the write. This capability cannot change 康纳同学's name."
    public let permission: AgentPermissionCapability = .mutatePersonality
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "proposalID": .string(description: "Exact proposalID returned by personality_propose_update; copy the field without renaming it.")
    ], required: ["proposalID"])

    private let runtime: ConnorPersonalityRuntime
    private let store: ConnorPersonalityProposalStore

    public init(runtime: ConnorPersonalityRuntime, store: ConnorPersonalityProposalStore) {
        self.runtime = runtime
        self.store = store
    }

    public func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws {
        try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(context.userPrompt)
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        _ = try await resolvedProposal(arguments)
    }

    public func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        guard let arguments = try? AgentToolArguments(json: call.argumentsJSON),
              let proposal = try? await resolvedProposal(arguments),
              let data = try? makePersonalityJSONEncoder().encode(ConnorPersonalityApprovalPayload(
                proposalID: proposal.id,
                title: proposal.mode == .reset ? "恢复康纳同学默认性格" : "更新康纳同学性格",
                lockedName: ConnorPersonalitySettings.lockedDisplayName,
                mode: proposal.mode,
                expectedRevision: proposal.expectedRevision,
                beforeSummary: proposal.before.summary,
                afterSummary: proposal.after.summary,
                after: proposal.after
              ))
        else { return call.argumentsJSON }
        return String(decoding: data, as: UTF8.self)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(context.userPrompt)
        let proposal = try await resolvedProposal(arguments)
        let current = try await runtime.snapshot()
        guard current.revision == proposal.expectedRevision else {
            throw ConnorPersonalityProposalError.revisionConflict(expected: proposal.expectedRevision, actual: current.revision)
        }
        let updated = try await runtime.commit(proposal)
        await store.markCommitted(id: proposal.id)
        let payload = ConnorPersonalityCommitPayload(
            proposalID: proposal.id,
            lockedName: ConnorPersonalitySettings.lockedDisplayName,
            revision: updated.revision,
            personality: updated.personality
        )
        return try personalityToolResult(
            payload,
            text: "人格配置已保存为版本 \(updated.revision)，将在后续对话中生效。康纳同学的姓名保持不变。",
            toolName: name,
            context: context
        )
    }

    private func resolvedProposal(_ arguments: AgentToolArguments) async throws -> ConnorPersonalityProposal {
        guard let id = (arguments.string("proposalID") ?? arguments.string("proposal_id"))?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw AgentToolError.invalidArguments("proposalID is required")
        }
        return try await store.proposal(id: id)
    }
}

public extension AgentToolRegistry {
    mutating func registerConnorPersonalityTools(runtime: ConnorPersonalityRuntime, provider: AnyAgentModelProvider) {
        register(ConnorPersonalityGetCurrentTool(runtime: runtime))
        register(ConnorPersonalityUpdateTool(runtime: runtime, provider: provider))
    }
}

private struct ConnorPersonalityCurrentPayload: Codable {
    var lockedName: String
    var revision: Int
    var personality: ConnorPersonalitySettings
}

private struct ConnorPersonalityProposalPayload: Codable {
    var proposalID: String
    var lockedName: String
    var mode: ConnorPersonalityUpdateMode
    var expectedRevision: Int
    var expiresAt: Date
    var before: ConnorPersonalitySettings
    var after: ConnorPersonalitySettings
    var requiresExplicitApproval: Bool
}

private struct ConnorPersonalityApprovalPayload: Codable {
    var proposalID: String
    var title: String
    var lockedName: String
    var mode: ConnorPersonalityUpdateMode
    var expectedRevision: Int
    var beforeSummary: String
    var afterSummary: String
    var after: ConnorPersonalitySettings
}

private struct ConnorPersonalityCommitPayload: Codable {
    var proposalID: String
    var lockedName: String
    var revision: Int
    var personality: ConnorPersonalitySettings
}

private func makePersonalityJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func personalityToolResult<Payload: Encodable>(
    _ payload: Payload,
    text: String,
    toolName: String,
    context: AgentToolExecutionContext
) throws -> AgentToolResult {
    let data = try makePersonalityJSONEncoder().encode(payload)
    return AgentToolResult(
        toolCallID: context.toolCallID,
        toolName: toolName,
        contentText: text,
        contentJSON: String(decoding: data, as: UTF8.self)
    )
}
