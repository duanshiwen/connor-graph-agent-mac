import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func extractionPromptBuilderIncludesSourceAndAllowedVocabulary() throws {
    let source = GraphExtractionSource(
        id: "chat-1",
        graphID: "default",
        sourceType: .chat,
        title: "Preference",
        content: "诗闻 prefers tea.",
        occurredAt: Date(timeIntervalSince1970: 1_000),
        sessionID: "session-1",
        workObjectID: "work-1"
    )
    let builder = GraphExtractionPromptBuilder(
        allowedPredicates: [.prefers, .relatedTo],
        allowedEntityKinds: [.personObject, .lifeObject],
        allowedScopes: [.personal, .project]
    )

    let prompt = builder.buildPrompt(for: source)

    #expect(prompt.contains("Output JSON only"))
    #expect(prompt.contains("PREFERS"))
    #expect(prompt.contains("RELATED_TO"))
    #expect(prompt.contains("person_object"))
    #expect(prompt.contains("life_object"))
    #expect(prompt.contains("Every statement must include at least one evidenceSpanID"))
    #expect(prompt.contains("诗闻 prefers tea."))
    #expect(prompt.contains("session-1"))
    #expect(prompt.contains("work-1"))
}
