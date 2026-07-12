import Foundation

public enum AnyAgentModelProviderError: Error, Sendable, Equatable, LocalizedError {
    case generatedMediaUnavailable(modelID: String)

    public var errorDescription: String? {
        switch self {
        case .generatedMediaUnavailable(let modelID):
            return "Model provider \(modelID) does not expose generated media execution."
        }
    }
}

public struct AnyAgentModelProvider: StreamingAgentModelProvider, AgentGeneratedMediaProvider {
    public let modelID: String
    public let capabilities: AgentModelCapabilities
    public let supportsGeneratedMediaExecution: Bool
    private let completeHandler: @Sendable (AgentModelRequest) async throws -> AgentModelResponse
    private let streamHandler: (@Sendable (AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error>)?
    private let generateMediaHandler: (@Sendable (AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error>)?

    public init<Provider: AgentModelProvider>(_ provider: Provider) {
        self.modelID = provider.modelID
        self.capabilities = provider.capabilities
        self.completeHandler = { request in try await provider.complete(request) }
        if let streamingProvider = provider as? any StreamingAgentModelProvider {
            self.streamHandler = { request in streamingProvider.streamComplete(request) }
        } else {
            self.streamHandler = nil
        }
        if let generatedMediaProvider = provider as? any AgentGeneratedMediaProvider {
            self.supportsGeneratedMediaExecution = true
            self.generateMediaHandler = { request in generatedMediaProvider.generateMedia(request) }
        } else {
            self.supportsGeneratedMediaExecution = false
            self.generateMediaHandler = nil
        }
    }

    public init<Provider: AgentGeneratedMediaProvider>(generatedMediaProvider provider: Provider) {
        self.modelID = provider.modelID
        self.capabilities = provider.capabilities
        self.supportsGeneratedMediaExecution = true
        self.completeHandler = { _ in throw AnyAgentModelProviderError.generatedMediaUnavailable(modelID: provider.modelID) }
        self.streamHandler = nil
        self.generateMediaHandler = { request in provider.generateMedia(request) }
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
        streamComplete: (@Sendable (AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error>)? = nil,
        generateMedia: (@Sendable (AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error>)? = nil
    ) {
        self.modelID = modelID
        self.capabilities = capabilities
        self.supportsGeneratedMediaExecution = generateMedia != nil
        self.completeHandler = complete
        self.streamHandler = streamComplete
        self.generateMediaHandler = generateMedia
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

    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        guard let generateMediaHandler else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AnyAgentModelProviderError.generatedMediaUnavailable(modelID: modelID))
            }
        }
        return generateMediaHandler(request)
    }
}
