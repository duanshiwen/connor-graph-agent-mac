import Foundation
import Testing
import SQLite3
import ConnorGraphCore
import ConnorGraphStore

@Suite("Atomic session persistence")
struct ChatSessionAtomicWriteTests {
    private struct SQLiteFailure: Error { let code: Int32 }

    private func installFailure(path: String, sql: String) throws {
        var database: OpaquePointer?
        let openResult = sqlite3_open(path, &database)
        defer { sqlite3_close(database) }
        guard openResult == SQLITE_OK else { throw SQLiteFailure(code: openResult) }
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw SQLiteFailure(code: result) }
    }

    private func withDatabase(_ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("sessions.sqlite").path)
    }

    @Test func failedMessageInsertPreservesPreviousMetadataAndPagesAfterReopen() throws {
        try withDatabase { path in
            let store = try SQLiteGraphKernelStore(path: path)
            try store.migrate()
            let original = AgentSession(id: "atomic", title: "Before", messages: [
                AgentMessage(id: "old", role: .user, content: "原始消息", createdAt: Date(timeIntervalSince1970: 1_000))
            ])
            try store.upsertSession(original)
            try installFailure(path: path, sql: """
                CREATE TRIGGER reject_test_message BEFORE INSERT ON agent_session_messages
                WHEN NEW.message_id = 'rejected'
                BEGIN SELECT RAISE(ABORT, 'injected insert failure'); END;
                """)
            var incoming = original
            incoming.title = "After"
            incoming.messages = [AgentMessage(id: "rejected", role: .assistant, content: "不应留下半次写入")]
            #expect(throws: (any Error).self) { try store.upsertSession(incoming) }

            let reopened = try SQLiteGraphKernelStore(path: path)
            let saved = try #require(try reopened.session(id: original.id))
            #expect(saved.title == original.title)
            #expect(saved.messages == original.messages)
            #expect(try reopened.sessionMessagePage(sessionID: original.id).messages == original.messages)
        }
    }

    @Test func failedFirstInsertDoesNotLeaveAnEmptySession() throws {
        try withDatabase { path in
            let store = try SQLiteGraphKernelStore(path: path)
            try store.migrate()
            try installFailure(path: path, sql: """
                CREATE TRIGGER reject_test_message BEFORE INSERT ON agent_session_messages
                BEGIN SELECT RAISE(ABORT, 'injected insert failure'); END;
                """)
            let session = AgentSession(id: "new", title: "Incomplete", messages: [
                AgentMessage(id: "new-message", role: .user, content: "test")
            ])
            #expect(throws: (any Error).self) { try store.upsertSession(session) }
            #expect(try store.session(id: session.id) == nil)
            #expect(try store.recentSessionMetadata().isEmpty)
        }
    }

    @Test func multiMegabyteSessionSurvivesReopenWithMatchingMessagePages() throws {
        try withDatabase { path in
            let session = AgentSession(id: "large", title: "Large sync", messages: [
                AgentMessage(id: "large-message", role: .assistant, content: String(repeating: "同😀", count: 500_000), createdAt: Date(timeIntervalSince1970: 1_000))
            ])
            do {
                let store = try SQLiteGraphKernelStore(path: path)
                try store.migrate()
                try store.upsertSession(session)
            }
            let reopened = try SQLiteGraphKernelStore(path: path)
            #expect(try reopened.session(id: session.id)?.messages == session.messages)
            #expect(try reopened.sessionMessagePage(sessionID: session.id).messages == session.messages)
        }
    }
}
