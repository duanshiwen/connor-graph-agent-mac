import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Chat Session Title Generation Worker Tests")
struct ChatSessionTitleGenerationWorkerTests {
    @Test func loadsTrimmedUserPromptsForTitleGeneration() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryTitleWorkerURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        let session = AgentSession(id: "session", messages: [
            AgentMessage(id: "user", role: .user, content: "  Please help  "),
            AgentMessage(id: "assistant", role: .assistant, content: "Done")
        ])
        try repository.saveSession(session)
        let worker = ChatSessionTitleGenerationWorker()

        let prompts = try await worker.userPrompts(repository: repository, sessionID: "session")

        #expect(prompts == ["Please help"])
    }

    @Test func renamesSessionThroughRepository() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryTitleWorkerURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        try repository.saveSession(AgentSession(id: "session", title: "Old"))
        let worker = ChatSessionTitleGenerationWorker()

        let updated = try await worker.renameSession(repository: repository, sessionID: "session", title: "New")

        #expect(updated.title == "New")
        #expect(try repository.loadSession(id: "session")?.title == "New")
    }
}

private func temporaryTitleWorkerURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chat-session-title-worker-\(UUID().uuidString).sqlite")
}
