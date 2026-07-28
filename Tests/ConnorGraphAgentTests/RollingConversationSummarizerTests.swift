import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphAgent

private actor RollingSummaryResponses {
    var values: [String]
    var prompts: [String] = []

    init(_ values: [String]) { self.values = values }

    func next(prompt: String) -> String {
        prompts.append(prompt)
        return values.removeFirst()
    }
}

private struct RollingSummaryProvider: LLMProvider {
    let responses: RollingSummaryResponses

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        LLMResponse(text: await responses.next(prompt: prompt), citations: [])
    }
}

@Test func rollingSummaryAdvancesAcrossMultipleCompressionGenerations() async throws {
    let firstPayload = ConversationSummaryPayload(
        currentGoal: "Build summaries",
        decisions: [.init(id: "decision-1", text: "Use one rolling summary", sourceMessageIDs: ["m1"])]
    )
    let secondPayload = ConversationSummaryPayload(
        currentGoal: "Build summaries",
        decisions: [.init(id: "decision-1", text: "Use one rolling summary", sourceMessageIDs: ["m1"])],
        pendingWork: [.init(id: "pending-1", text: "Wire runtime", sourceMessageIDs: ["m5"])]
    )
    let encoder = JSONEncoder()
    let responses = RollingSummaryResponses([
        String(decoding: try encoder.encode(firstPayload), as: UTF8.self),
        String(decoding: try encoder.encode(secondPayload), as: UTF8.self)
    ])
    let summarizer = RollingConversationSummarizer(
        provider: RollingSummaryProvider(responses: responses),
        modelID: "test-model"
    )
    let planner = ConversationCompactionPlanner(recentTailTokenRatio: 0.20, minimumRecentMessageCount: 2)
    let initial = (1...6).map { index in
        AgentMessage(id: "m\(index)", role: index.isMultiple(of: 2) ? .assistant : .user, content: String(repeating: "message \(index) ", count: 20))
    }

    let firstPlan = try planner.plan(messages: initial, existingState: nil, contextWindowTokens: 100)
    let firstDraft = try await summarizer.summarize(
        sessionID: "session",
        plan: firstPlan,
        now: Date(timeIntervalSince1970: 10)
    )
    let expanded = initial + (7...10).map { index in
        AgentMessage(id: "m\(index)", role: index.isMultiple(of: 2) ? .assistant : .user, content: String(repeating: "message \(index) ", count: 20))
    }
    let secondPlan = try planner.plan(messages: expanded, existingState: firstDraft.state, contextWindowTokens: 100)
    let secondDraft = try await summarizer.summarize(
        sessionID: "session",
        plan: secondPlan,
        now: Date(timeIntervalSince1970: 20)
    )

    #expect(firstDraft.state.compressionGeneration == 1)
    #expect(secondDraft.state.compressionGeneration == 2)
    #expect(secondDraft.state.revision == 2)
    #expect(secondDraft.state.previousSummaryHash == firstDraft.state.currentSummaryHash)
    #expect(secondDraft.record.previousCutoffMessageID == firstDraft.state.coveredThroughMessageID)
    #expect(secondDraft.record.deltaMessageIDs.allSatisfy { !firstDraft.record.deltaMessageIDs.contains($0) })
    #expect(secondDraft.state.payload.decisions.map(\.id).contains("decision-1"))
    #expect(await responses.prompts.count == 2)
    #expect(await responses.prompts[1].contains("decision-1"))
}

@Test func rollingSummaryRejectsDroppedActiveItems() async throws {
    let previous = ConversationSummaryPayload(
        currentGoal: "Goal",
        decisions: [.init(id: "must-keep", text: "Keep this")]
    )
    let empty = ConversationSummaryPayload(currentGoal: "Goal")
    let encoder = JSONEncoder()
    let responses = RollingSummaryResponses([String(decoding: try encoder.encode(empty), as: UTF8.self)])
    let state = ConversationSummaryState(
        sessionID: "session",
        revision: 1,
        compressionGeneration: 1,
        payload: previous,
        coveredThroughMessageID: "m2",
        coveredMessageCount: 2,
        coveredPrefixHash: "prefix",
        currentSummaryHash: "summary",
        sourceTokenEstimate: 20,
        summaryTokenEstimate: 10,
        generationModelID: "model"
    )
    let messages = (1...6).map { AgentMessage(id: "m\($0)", role: $0.isMultiple(of: 2) ? .assistant : .user, content: "message \($0)") }
    let plan = try ConversationCompactionPlanner(minimumRecentMessageCount: 2).plan(
        messages: messages,
        existingState: state,
        contextWindowTokens: 20
    )
    let summarizer = RollingConversationSummarizer(provider: RollingSummaryProvider(responses: responses), modelID: "model")

    await #expect(throws: RollingConversationSummaryError.requiredItemsMissing(["must-keep"])) {
        _ = try await summarizer.summarize(sessionID: "session", plan: plan)
    }
}
