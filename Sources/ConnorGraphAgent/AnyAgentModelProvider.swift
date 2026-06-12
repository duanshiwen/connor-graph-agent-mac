import Foundation

public struct AnyAgentModelProvider: AgentModelProvider {
    public let modelID: String
    public let capabilities: AgentModelCapabilities
    private let completeHandler: @Sendable (AgentModelRequest) async throws -> AgentModelResponse

    public init<Provider: AgentModelProvider>(_ provider: Provider) {
        self.modelID = provider.modelID
        self.capabilities = provider.capabilities
        self.completeHandler = { request in try await provider.complete(request) }
    }

    public init(
        modelID: String,
        capabilities: AgentModelCapabilities = AgentModelCapabilities(
            supportsStreaming: false,
            supportsToolCalling: false,
            supportsParallelToolCalls: false,
            supportsStructuredOutput: false,
            supportsVision: false
        ),
        complete: @escaping @Sendable (AgentModelRequest) async throws -> AgentModelResponse
    ) {
        self.modelID = modelID
        self.capabilities = capabilities
        self.completeHandler = complete
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await completeHandler(request)
    }
}
