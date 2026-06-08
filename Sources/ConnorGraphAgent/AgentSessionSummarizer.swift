import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct AgentSessionSummarizer<Provider: LLMProvider>: Sendable {
    public var provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func summarize(session: AgentSession) async throws -> AgentSessionSummary {
        let prompt = Self.prompt(for: session)
        let context = AgentContext(query: "Summarize chat session", items: [])
        let response = try await provider.complete(prompt: prompt, context: context)
        let now = Date()
        return AgentSessionSummary(
            sessionID: session.id,
            content: response.text,
            createdAt: now,
            updatedAt: now,
            sourceMessageCount: session.messages.count,
            lastMessageID: session.messages.last?.id
        )
    }

    private static func prompt(for session: AgentSession) -> String {
        let transcript = session.messages.map { message in
            "\(message.role.rawValue.capitalized): \(message.content)"
        }.joined(separator: "\n\n")

        return """
        Summarize this chat session for future context compaction.

        Requirements:
        - Capture the user's goals, important decisions, implementation details, and unresolved next steps.
        - Preserve concrete identifiers, file paths, branch names, and commands when relevant.
        - Be concise but specific enough that another agent can resume the work.
        - Do not invent details not present in the transcript.

        Session title: \(session.title)
        Session ID: \(session.id)

        Transcript:
        \(transcript)
        """
    }
}
