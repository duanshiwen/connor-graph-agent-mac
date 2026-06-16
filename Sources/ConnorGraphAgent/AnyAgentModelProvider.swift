import Foundation

public struct AnyAgentModelProvider: StreamingAgentModelProvider {
    public let modelID: String
    public let capabilities: AgentModelCapabilities
    private let completeHandler: @Sendable (AgentModelRequest) async throws -> AgentModelResponse
    private let streamHandler: (@Sendable (AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error>)?

    public init<Provider: AgentModelProvider>(_ provider: Provider) {
        self.modelID = provider.modelID
        self.capabilities = provider.capabilities
        self.completeHandler = { request in try await provider.complete(request) }
        if let streamingProvider = provider as? any StreamingAgentModelProvider {
            self.streamHandler = { request in streamingProvider.streamComplete(request) }
        } else {
            self.streamHandler = nil
        }
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
        complete: @escaping @Sendable (AgentModelRequest) async throws -> AgentModelResponse,
        streamComplete: (@Sendable (AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error>)? = nil
    ) {
        self.modelID = modelID
        self.capabilities = capabilities
        self.completeHandler = complete
        self.streamHandler = streamComplete
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await completeHandler(request)
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        if let streamHandler { return streamHandler(request) }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.completed(try await completeHandler(request)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
