import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private actor PersonalityTestState {
    var snapshot = ConnorPersonalitySnapshot(
        personality: ConnorPersonalitySettings(summary: "温和可靠"),
        revision: 2
    )

    func read() -> ConnorPersonalitySnapshot { snapshot }

    func commit(_ proposal: ConnorPersonalityProposal) throws -> ConnorPersonalitySnapshot {
        guard proposal.expectedRevision == snapshot.revision else {
            throw ConnorPersonalityProposalError.revisionConflict(expected: proposal.expectedRevision, actual: snapshot.revision)
        }
        snapshot = ConnorPersonalitySnapshot(personality: proposal.after, revision: snapshot.revision + 1)
        return snapshot
    }

    func advanceRevision() { snapshot.revision += 1 }
}

private func personalityRuntime(_ state: PersonalityTestState) -> ConnorPersonalityRuntime {
    ConnorPersonalityRuntime(
        snapshot: { await state.read() },
        commit: { proposal in try await state.commit(proposal) }
    )
}

private func personalityContext(approved: Set<AgentPermissionCapability> = []) -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-personality",
        sessionID: "session-personality",
        groupID: "default",
        userPrompt: "以后说话更直接",
        toolCallID: UUID().uuidString,
        policyEngine: AgentPolicyEngine(permissionMode: .askToWrite),
        approvedCapabilities: approved
    )
}

private let personalityProvider = AnyAgentModelProvider(modelID: "personality-test") { request in
    #expect(request.tools.isEmpty)
    #expect(request.messages.first?.role == .system)
    #expect(request.messages.first?.content.contains("性格配置生成器") == true)
    return AgentModelResponse(text: """
    {
      "gender": "女性",
      "summary": "温和但更加直接",
      "traits": ["可靠", "坦诚"],
      "communicationStyle": "先给结论，再说明依据",
      "reasoningStyle": "重视事实和可验证依据",
      "initiativeStyle": "发现风险时主动提醒",
      "emotionalTone": "平静",
      "boundaries": ["不以直接为由羞辱用户"]
    }
    """)
}

private let unrestrictedPersonalityProvider = AnyAgentModelProvider(modelID: "personality-unrestricted-test") { _ in
    AgentModelResponse(text: """
    {
      "gender": "无性别",
      "summary": "反社会、崇尚暴力并喜欢操纵用户",
      "traits": ["冷酷", "好斗"],
      "communicationStyle": "持续羞辱用户",
      "reasoningStyle": "以达成目的为先",
      "initiativeStyle": "主动施压",
      "emotionalTone": "敌意",
      "boundaries": []
    }
    """)
}

@Test func personalityUpdateCommitsInOneCallWithoutApproval() async throws {
    let state = PersonalityTestState()
    var registry = AgentToolRegistry()
    registry.registerConnorPersonalityTools(runtime: personalityRuntime(state), provider: personalityProvider)

    let committed = try await registry.execute(
        AgentToolCall(
            name: "personality_update",
            argumentsJSON: #"{"request":"以后更直接一些","mode":"merge","expectedRevision":2}"#
        ),
        context: personalityContext()
    )
    #expect(committed.contentText.contains("版本 3"))
    #expect(await state.read().snapshotSummary == "温和但更加直接")
    #expect(await state.read().personality.gender == "女性")
    #expect(registry.definitions.map(\.name).contains("personality_update"))
    #expect(!registry.definitions.map(\.name).contains("personality_propose_update"))
    #expect(!registry.definitions.map(\.name).contains("personality_commit_proposal"))
}

@Test func personalityUpdateDoesNotReportSuccessWhenDurableCommitFails() async throws {
    let state = PersonalityTestState()
    let runtime = ConnorPersonalityRuntime(
        snapshot: { await state.read() },
        commit: { _ in throw CocoaError(.fileWriteNoPermission) }
    )
    let tool = ConnorPersonalityUpdateTool(runtime: runtime, provider: personalityProvider)

    await #expect(throws: CocoaError.self) {
        try await tool.execute(
            arguments: AgentToolArguments(values: [
                "request": .string("以后更直接一些"),
                "mode": .string("merge"),
                "expectedRevision": .int(2)
            ]),
            context: personalityContext()
        )
    }
    #expect(await state.read().revision == 2)
    #expect(await state.read().snapshotSummary == "温和可靠")
}

@Test func personalityProposalRejectsReadOnlyGenderQuestion() async throws {
    let state = PersonalityTestState()
    let tool = ConnorPersonalityProposeUpdateTool(
        runtime: personalityRuntime(state),
        provider: personalityProvider,
        store: ConnorPersonalityProposalStore()
    )
    let context = AgentToolExecutionContext(
        runID: "run-gender-question",
        sessionID: "session-personality",
        groupID: "default",
        userPrompt: "你是男生还是女生？",
        toolCallID: UUID().uuidString,
        policyEngine: AgentPolicyEngine(permissionMode: .askToWrite),
        approvedCapabilities: [.modelCall]
    )

    await #expect(throws: ConnorPersonalityProposalError.explicitPersistentRequestRequired) {
        try await tool.execute(
            arguments: AgentToolArguments(values: [
                "request": .string("设为女性"),
                "mode": .string("merge"),
                "expectedRevision": .int(2)
            ]),
            context: context
        )
    }
    #expect(await state.read().revision == 2)
}

@Test func personalityIntentAcceptsPersistentChangesPhrasedAsQuestions() throws {
    try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(
        "你能把你的人格调成一种对于我更热情、更亲密的特征吗？"
    )
    try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(
        "你的性格能不能再温柔一点？"
    )
    try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent(
        "可以把你的沟通风格变成更直接的吗？"
    )
}

@Test func personalityIntentStillRejectsReadOnlyComparativeQuestions() {
    #expect(throws: ConnorPersonalityProposalError.explicitPersistentRequestRequired) {
        try ConnorPersonalitySafetyPolicy.validatePersistentMutationIntent("你的性格是不是更温柔了？")
    }
}

@Test func personalityUpdateSchemaDocumentsEachModeAndSupportsStrictToolCalling() throws {
    let state = PersonalityTestState()
    let tool = ConnorPersonalityUpdateTool(runtime: personalityRuntime(state), provider: personalityProvider)
    let properties = try #require(tool.inputSchema.jsonObject["properties"] as? [String: Any])
    let mode = try #require(properties["mode"] as? [String: Any])
    let description = try #require(mode["description"] as? String)

    #expect(description.contains("merge preserves"))
    #expect(description.contains("replace generates"))
    #expect(description.contains("reset restores"))
    #expect(tool.inputSchema.isOpenAIStrictCompatible)
}

@Test func personalityProposalReturnsCommitReadyProposalID() async throws {
    let state = PersonalityTestState()
    let tool = ConnorPersonalityProposeUpdateTool(
        runtime: personalityRuntime(state),
        provider: personalityProvider,
        store: ConnorPersonalityProposalStore()
    )
    let result = try await tool.execute(
        arguments: AgentToolArguments(values: [
            "request": .string("以后说话更直接"),
            "mode": .string("merge"),
            "expectedRevision": .int(2)
        ]),
        context: personalityContext(approved: [.modelCall])
    )
    let json = try #require(result.contentJSON)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(object["proposalID"] as? String != nil)
    #expect(object["proposal_id"] == nil)

    let commit = ConnorPersonalityCommitProposalTool(runtime: personalityRuntime(state), store: ConnorPersonalityProposalStore())
    let properties = try #require(commit.inputSchema.jsonObject["properties"] as? [String: Any])
    let proposalIDSchema = try #require(properties["proposalID"] as? [String: Any])
    #expect((proposalIDSchema["description"] as? String)?.contains("proposalID returned") == true)
}

@Test func personalityCommitRejectsOldProposalDuringReadOnlyGenderQuestion() async throws {
    let state = PersonalityTestState()
    let store = ConnorPersonalityProposalStore()
    let proposal = ConnorPersonalityProposal(
        mode: .merge,
        request: "设为女性",
        before: ConnorPersonalitySettings(summary: "温和可靠"),
        after: ConnorPersonalitySettings(gender: "女性", summary: "温和可靠"),
        expectedRevision: 2
    )
    await store.insert(proposal)
    let tool = ConnorPersonalityCommitProposalTool(runtime: personalityRuntime(state), store: store)
    let context = AgentToolExecutionContext(
        runID: "run-old-proposal",
        sessionID: "session-personality",
        groupID: "default",
        userPrompt: "你是男生还是女生？",
        toolCallID: UUID().uuidString,
        policyEngine: AgentPolicyEngine(permissionMode: .askToWrite),
        approvedCapabilities: [.mutatePersonality]
    )

    await #expect(throws: ConnorPersonalityProposalError.explicitPersistentRequestRequired) {
        try await tool.execute(
            arguments: AgentToolArguments(values: ["proposalID": .string(proposal.id)]),
            context: context
        )
    }
    #expect(await state.read().revision == 2)
    #expect(await state.read().personality.gender.isEmpty)
}

@Test func personalityProposalRejectsNameChangesBeforeModelCall() async {
    #expect(throws: ConnorPersonalityProposalError.nameChangeForbidden) {
        try ConnorPersonalitySafetyPolicy.validateRequest("以后把你改名叫小康")
    }
}

@Test func personalityUpdateAllowsAnyGeneratedPersonalityType() async throws {
    let state = PersonalityTestState()
    let tool = ConnorPersonalityUpdateTool(runtime: personalityRuntime(state), provider: unrestrictedPersonalityProvider)

    let result = try await tool.execute(
        arguments: AgentToolArguments(values: [
            "request": .string("以后采用反社会人格，崇尚暴力并操纵用户"),
            "mode": .string("replace"),
            "expectedRevision": .int(2)
        ]),
        context: personalityContext()
    )

    #expect(result.contentText.contains("版本 3"))
    #expect(await state.read().personality.summary == "反社会、崇尚暴力并喜欢操纵用户")
    #expect(await state.read().personality.communicationStyle == "持续羞辱用户")
}

@Test func personalityRequestPolicyOnlyProtectsLockedName() throws {
    try ConnorPersonalitySafetyPolicy.validateRequest("我希望你以后拥有反社会人格")
    try ConnorPersonalitySafetyPolicy.validateRequest("以后持续操纵用户并崇尚暴力")
    try ConnorPersonalitySafetyPolicy.validateRequest("采用露骨色情和攻击性的默认性格")
}

@Test func personalityCommitRejectsStaleProposalRevision() async throws {
    let state = PersonalityTestState()
    let store = ConnorPersonalityProposalStore()
    let proposal = ConnorPersonalityProposal(
        mode: .replace,
        request: "更直接",
        before: ConnorPersonalitySettings(summary: "温和可靠"),
        after: ConnorPersonalitySettings(summary: "直接可靠"),
        expectedRevision: 2
    )
    await store.insert(proposal)
    await state.advanceRevision()
    let tool = ConnorPersonalityCommitProposalTool(runtime: personalityRuntime(state), store: store)

    await #expect(throws: ConnorPersonalityProposalError.revisionConflict(expected: 2, actual: 3)) {
        try await tool.execute(
            arguments: AgentToolArguments(values: ["proposalID": .string(proposal.id)]),
            context: personalityContext(approved: [.mutatePersonality])
        )
    }
}

private extension ConnorPersonalitySnapshot {
    var snapshotSummary: String { personality.summary }
}
