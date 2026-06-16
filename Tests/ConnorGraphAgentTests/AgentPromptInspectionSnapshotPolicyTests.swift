import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func promptInspectionSnapshotPolicyKeepsPromptInspectionMetadata() {
    let inspection = AgentChatPromptInspection(
        includesSummary: true,
        recentMessageCount: 3,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt"
    )
    let policy = AgentPromptInspectionSnapshotPolicy()

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.includesSummary)
    #expect(snapshot.recentMessageCount == 3)
    #expect(snapshot.currentRequest == "What next?")
    #expect(snapshot.renderedPrompt == nil)
}

@Test func promptInspectionSnapshotPolicyCanOmitRenderedPrompt() {
    let inspection = AgentChatPromptInspection(
        includesSummary: false,
        recentMessageCount: 1,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt"
    )
    let policy = AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: false)

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.renderedPrompt == nil)
}

@Test func promptInspectionSnapshotPolicyTruncatesRenderedPrompt() {
    let inspection = AgentChatPromptInspection(
        includesSummary: false,
        recentMessageCount: 0,
        currentRequest: "What next?",
        renderedPrompt: "abcdefghijklmnopqrstuvwxyz"
    )
    let policy = AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: true, maxRenderedPromptCharacters: 10)

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.renderedPrompt == "abcdefghij… [truncated]")
}

@Test func promptInspectionSnapshotPolicyRedactsBearerTokensAPIKeysAndEmails() {
    let inspection = AgentChatPromptInspection(
        includesSummary: true,
        recentMessageCount: 2,
        currentRequest: "Email me at user@example.com",
        renderedPrompt: "Authorization: Bearer sk-secret123\napi_key=abc123\nContact user@example.com"
    )
    let policy = AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: true)

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.currentRequest == "Email me at user@example.com")
    #expect(snapshot.renderedPrompt?.contains("Bearer [REDACTED]") == true)
    #expect(snapshot.renderedPrompt?.contains("api_key=[REDACTED]") == true)
    #expect(snapshot.renderedPrompt?.contains("[REDACTED_EMAIL]") == true)
    #expect(snapshot.renderedPrompt?.contains("sk-secret123") == false)
    #expect(snapshot.renderedPrompt?.contains("abc123") == false)
    #expect(snapshot.renderedPrompt?.contains("user@example.com") == false)
}

@Test func promptInspectionSnapshotPolicyCarriesOriginalPromptBudgetWhenPromptIsOmitted() {
    let inspection = AgentChatPromptInspection(
        includesSummary: false,
        recentMessageCount: 1,
        currentRequest: "What next?",
        renderedPrompt: "abcdefghij"
    )
    let policy = AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: false)

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.renderedPrompt == nil)
    #expect(snapshot.renderedPromptCharacterCount == 10)
    #expect(snapshot.estimatedPromptTokenCount == 3)
    #expect(snapshot.promptBudgetStatus == .safe)
}

@Test func promptInspectionSnapshotPolicyCarriesPromptBudgetStatusWhenPromptIsOmitted() {
    let inspection = AgentChatPromptInspection(
        includesSummary: false,
        recentMessageCount: 1,
        currentRequest: "What next?",
        renderedPrompt: String(repeating: "a", count: 32_000)
    )
    let policy = AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: false)

    let snapshot = policy.snapshot(for: inspection)

    #expect(snapshot.renderedPrompt == nil)
    #expect(snapshot.estimatedPromptTokenCount == AgentPromptBudgetEstimator().estimate(inspection.renderedPrompt).estimatedTokenCount)
    #expect(snapshot.promptBudgetStatus == .over)
}
