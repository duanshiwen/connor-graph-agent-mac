import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Note Edit Persistence Tests")
struct NoteEditPersistenceTests {
    private func makeHarness() throws -> (repository: AppChatSessionRepository, notes: AppNoteRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-note-edit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store, storagePaths: paths)
        return (repository, AppNoteRepository(store: store))
    }

    private func context() -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-note-edit",
            sessionID: "session",
            groupID: "group",
            userPrompt: "edit note",
            toolCallID: UUID().uuidString,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }

    @Test func noteEditUpdatesSessionBodyAndNoteProjection() async throws {
        let (repository, notes) = try makeHarness()
        let create = NoteCreateTool(repository: repository, noteRepository: notes)
        let created = try await create.execute(
            arguments: try AgentToolArguments(json: #"{"title":"客服记录","content":"原始正文"}"#),
            context: context()
        )
        let createdJSON = try #require(created.contentJSON)
        let createdObject = try JSONSerialization.jsonObject(with: Data(createdJSON.utf8)) as? [String: Any]
        let id = try #require(createdObject?["noteID"] as? String)

        let edit = NoteEditTool(repository: repository, noteRepository: notes)
        let edited = try await edit.execute(
            arguments: try AgentToolArguments(json: #"{"noteID":"\#(id)","content":"修改后的正文"}"#),
            context: context()
        )
        #expect(edited.contentText.contains("已更新笔记"))

        guard let note = try notes.note(id: id) else {
            Issue.record("note not found after edit")
            return
        }
        #expect(note.body == "修改后的正文")

        guard let session = try repository.loadSession(id: note.sessionID) else {
            Issue.record("session not found after edit")
            return
        }
        #expect(session.messages.first?.content == "修改后的正文")
    }
}
