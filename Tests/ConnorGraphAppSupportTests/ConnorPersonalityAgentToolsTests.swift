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

@Test func personalityUpdateCommitsInOneCallWithoutApproval() async throws {
    let state = PersonalityTestState()
    var registry = AgentToolRegistry()
    registry.registerConnorPersonalityTools(runtime: personalityRuntime(state), provider: personalityProvider)

    let committed = try await registry.execute(
        AgentToolCall(
            name: "personality_update",
            argumentsJSON: #"{"request":"以后更直接一些","mode":"merge","expected_revision":2}"#
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
                "expected_revision": .int(2)
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
                "expected_revision": .int(2)
            ]),
            context: context
        )
    }
    #expect(await state.read().revision == 2)
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
            arguments: AgentToolArguments(values: ["proposal_id": .string(proposal.id)]),
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
    #expect(throws: ConnorPersonalityProposalError.unsafePersonality(category: "伤害、虐待或暴力美化")) {
        try ConnorPersonalitySafetyPolicy.validateRequest("我希望你以后拥有反社会人格")
    }
}

@Test func personalitySafetyPolicyRejectsHarmfulBehaviorButAllowsRestrainedBoundaries() throws {
    #expect(throws: ConnorPersonalityProposalError.unsafePersonality(category: "欺骗、操纵或违法煽动")) {
        try ConnorPersonalitySafetyPolicy.validatePersonality(
            ConnorPersonalitySettings(summary: "擅长操纵用户来服从自己的决定")
        )
    }

    try ConnorPersonalitySafetyPolicy.validatePersonality(
        ConnorPersonalitySettings(
            summary: "冷静、坦诚",
            boundaries: ["讨论暴力新闻时保持克制，不描述露骨细节"]
        )
    )
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
            arguments: AgentToolArguments(values: ["proposal_id": .string(proposal.id)]),
            context: personalityContext(approved: [.mutatePersonality])
        )
    }
}

private extension ConnorPersonalitySnapshot {
    var snapshotSummary: String { personality.summary }
}
