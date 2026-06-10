import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private actor NativeSessionFinalAnswerProvider: AgentModelProvider {
    let modelID = "native-session-final-answer"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(
            text: "Connor-owned assistant response",
            usage: AgentModelUsage(promptTokens: 8, completionTokens: 4)
        )
    }
}

private enum NativeSessionFailingProviderError: Error, Sendable, Equatable {
    case backendUnavailable
}

private actor NativeSessionFailingProvider: AgentModelProvider {
    let modelID = "native-session-failing-provider"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: false,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        throw NativeSessionFailingProviderError.backendUnavailable
    }
}

private func temporaryNativeSessionManagerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func makeNativeSessionStore() throws -> SQLiteGraphKernelStore {
    let store = try SQLiteGraphKernelStore(path: temporaryNativeSessionManagerDatabaseURL().path)
    try store.migrate()
    return store
}

@Test func nativeSessionManagerPersistsUserMessageBeforeBackendCompletes() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-1", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let loop = AgentLoopController(modelProvider: NativeSessionFinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let response = try await manager.submit("Build a native SessionManager")
    let loaded = try #require(try repository.loadSession(id: "native-session-1"))

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.first?.content == "Build a native SessionManager")
    #expect(loaded.messages.last?.content == "Connor-owned assistant response")
    #expect(manager.session.messages.map(\.id) == loaded.messages.map(\.id))
    #expect(manager.session.messages.map(\.role) == loaded.messages.map(\.role))
    #expect(manager.session.messages.map(\.content) == loaded.messages.map(\.content))
}

@Test func nativeSessionManagerPreservesUserMessageWhenBackendFails() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-failure", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let loop = AgentLoopController(modelProvider: NativeSessionFailingProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    do {
        _ = try await manager.submit("This must be durable even if the backend fails")
        Issue.record("Expected backend failure")
    } catch NativeSessionFailingProviderError.backendUnavailable {
        // expected
    }

    let loaded = try #require(try repository.loadSession(id: "native-session-failure"))
    #expect(loaded.messages.count == 1)
    #expect(loaded.messages.first?.role == .user)
    #expect(loaded.messages.first?.content == "This must be durable even if the backend fails")
    #expect(manager.session.messages.map(\.id) == loaded.messages.map(\.id))
    #expect(manager.session.messages.map(\.role) == loaded.messages.map(\.role))
    #expect(manager.session.messages.map(\.content) == loaded.messages.map(\.content))
}
