import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct AgentChatController<Provider: LLMProvider>: Sendable {
    public private(set) var agent: GraphAgent<Provider>
    public private(set) var transcript: [AgentMessage]
    public private(set) var lastContext: AgentContext?

    public init(agent: GraphAgent<Provider>) {
        self.agent = agent
        self.transcript = agent.session.messages
        self.lastContext = nil
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> GraphAgentAskResponse {
        let response = try await agent.ask(prompt)
        agent.session = response.session
        transcript = response.session.messages
        lastContext = response.context
        return response
    }
}
