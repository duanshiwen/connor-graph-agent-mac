import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private struct CoordinatorBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> { AsyncThrowingStream { c in var run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running); c.yield(.runStarted(.init(run: run))); c.yield(.textComplete(.init(runID: request.runID, sessionID: request.sessionID, text: "Done", citations: []))); run.status = .completed; c.yield(.runCompleted(.init(run: run))); c.finish() } }
}

private final class FlakyCoordinatorBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresRemaining: Int
    private(set) var callCount = 0

    init(failures: Int) { failuresRemaining = failures }

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        lock.lock()
        callCount += 1
        let shouldFail = failuresRemaining > 0
        failuresRemaining = max(failuresRemaining - 1, 0)
        lock.unlock()
        if shouldFail {
            return AsyncThrowingStream { $0.finish(throwing: NoteImportProviderFailure.transient("offline")) }
        }
        return CoordinatorBackend().chat(request)
    }
}

private final class ImportedSessionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [AgentSession] = []

    func append(_ session: AgentSession) {
        lock.withLock { sessions.append(session) }
    }

    var snapshot: [AgentSession] {
        lock.withLock { sessions }
    }
}

private struct SingleNoteAdapter: NoteImportSourceAdapter {
    let note: ImportedNote
    var sourceKind: NoteImportSourceKind { note.sourceKind }
    func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(note)
            continuation.finish()
        }
    }
}

@Suite("Note import coordinator")
struct NoteImportCoordinatorTests {
    @Test("Scans, creates note sessions, and processes them headlessly")
    func endToEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        try Data("# First\nBody".utf8).write(to: root.appendingPathComponent("first.md"))
        try Data("# Second\nBody".utf8).write(to: root.appendingPathComponent("second.md"))
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("db.sqlite").path); try store.migrate()
        let chat = AppChatSessionRepository(store: store); let ledger = try AppNoteImportRepository(databasePath: root.appendingPathComponent("db.sqlite").path)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"); try ledger.saveSource(source)
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, options: .init(llmMode: .automatic)); try ledger.saveJob(job)
        let sessionService = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let recorder = ImportedSessionRecorder()
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: sessionService, onSessionImported: recorder.append)
        let request = NoteImportScanRequest(sourceID: source.id, sourceURL: root, kind: .markdownFolder, options: job.options)
        #expect(try await coordinator.scan(jobID: job.id, adapter: MarkdownFolderNoteImportAdapter(), request: request).status == .awaitingReview)
        #expect(try await coordinator.execute(jobID: job.id).status == .completed)
        let progress = try await coordinator.progress(jobID: job.id)
        #expect(progress.discovered == 2); #expect(progress.completed == 2); #expect(progress.failed == 0)
        let sessions = try chat.loadRecentSessions(limit: 10)
        #expect(sessions.count == 2); #expect(sessions.allSatisfy { $0.governance.kind == .note && $0.messages.count == 3 })
        #expect(Set(recorder.snapshot.map(\.id)) == Set(sessions.map(\.id)))
        #expect(sessions.allSatisfy { session in recorder.snapshot.contains { $0.id == session.id && $0.messages.count == session.messages.count } })
    }

    @Test("Resumes an imported item at the LLM phase without recreating its session")
    func resumesImportedItemWithoutRecreatingSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let store = try SQLiteGraphKernelStore(path: databasePath)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try ledger.saveSource(source)
        let job = NoteImportJobRecord(
            id: "job",
            sourceID: source.id,
            status: .processing,
            options: .init(llmMode: .automatic),
            discoveredCount: 1,
            importedCount: 1
        )
        try ledger.saveJob(job)
        let existingSession = try chat.createImportedNoteSession(title: "Existing", content: "Original")
        let payload = ImportedNote(
            sourceKind: .markdownFolder,
            sourceIdentity: "note.md",
            title: "Existing",
            markdownContent: "Original",
            rawByteHash: "raw",
            normalizedTextHash: "text"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try ledger.saveItem(NoteImportItemRecord(
            id: "item",
            jobID: job.id,
            sourceID: source.id,
            sourceIdentity: payload.sourceIdentity,
            title: payload.title,
            status: .imported,
            sessionID: existingSession.id,
            rawByteHash: payload.rawByteHash,
            normalizedTextHash: payload.normalizedTextHash,
            metadata: ["imported_note_payload": try encoder.encode(payload).base64EncodedString()]
        ))
        let sessionService = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session)
        }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: sessionService)

        let completed = try await coordinator.execute(jobID: job.id)

        #expect(completed.status == .completed)
        #expect(try ledger.item(id: "item")?.status == .completed)
        let sessions = try chat.loadRecentSessions(limit: 10)
        #expect(sessions.count == 1)
        #expect(sessions[0].id == existingSession.id)
    }

    @Test("Imports original note content without requiring LLM processing")
    func importsWithoutLLM() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# 原始笔记\n不会因为关闭 AI 而丢失。".utf8).write(to: root.appendingPathComponent("note.md"))
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("db.sqlite").path)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: root.appendingPathComponent("db.sqlite").path)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try ledger.saveSource(source)
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, options: .init(llmMode: .disabled))
        try ledger.saveJob(job)
        let sessionService = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session)
        }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: sessionService)
        let request = NoteImportScanRequest(sourceID: source.id, sourceURL: root, kind: .markdownFolder, options: job.options)

        _ = try await coordinator.scan(jobID: job.id, adapter: MarkdownFolderNoteImportAdapter(), request: request)
        _ = try await coordinator.execute(jobID: job.id)

        let sessions = try chat.loadRecentSessions(limit: 10)
        #expect(sessions.count == 1)
        #expect(sessions[0].messages.count == 1)
        #expect(sessions[0].messages[0].content.contains("不会因为关闭 AI 而丢失"))
        #expect(try ledger.jobs().map(\.id) == [job.id])
        #expect(try ledger.sources().map(\.id) == [source.id])
    }

    @Test("Persists original content first and retries transient LLM failures idempotently")
    func retriesTransientLLMWithoutDuplicatingProcessingMessages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let store = try SQLiteGraphKernelStore(path: databasePath)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try ledger.saveSource(source)
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, options: .init(llmMode: .automatic))
        try ledger.saveJob(job)
        let backend = FlakyCoordinatorBackend(failures: 1)
        let service = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: backend, sessionRepository: chat, session: session)
        }
        let coordinator = NoteImportCoordinator(
            ledger: ledger,
            sessionService: service,
            retryPolicy: .init(maxAttempts: 3, initialDelay: 0, maximumDelay: 0)
        )
        let note = ImportedNote(
            sourceKind: .markdownFolder,
            sourceIdentity: "note.md",
            title: "Important",
            markdownContent: "Original body that must survive.",
            rawByteHash: "raw",
            normalizedTextHash: "text"
        )

        _ = try await coordinator.scan(
            jobID: job.id,
            adapter: SingleNoteAdapter(note: note),
            request: .init(sourceID: source.id, sourceURL: root, kind: .markdownFolder, options: job.options)
        )
        let completed = try await coordinator.execute(jobID: job.id)

        #expect(completed.status == .completed)
        let item = try #require(ledger.items(jobID: job.id).first)
        #expect(item.attemptCount == 2)
        #expect(item.leaseOwner == nil)
        #expect(item.nextRetryAt == nil)
        #expect(backend.callCount == 2)
        let loadedSession = try chat.loadSession(id: "note-import-session:\(item.id)")
        let session = try #require(loadedSession)
        #expect(session.messages.first?.id == "note-import-message:\(item.id)")
        #expect(session.messages.first?.content == note.markdownContent)
        #expect(session.messages.count == 3)
    }

    @Test("Reuses deterministic session after interruption between session creation and ledger binding")
    func reusesSessionAfterBindingInterruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let store = try SQLiteGraphKernelStore(path: databasePath)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        try ledger.saveSource(.init(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try ledger.saveJob(.init(id: "job", sourceID: "source", status: .importing, options: .init(llmMode: .disabled), discoveredCount: 1))
        let note = ImportedNote(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "Note", markdownContent: "Original", rawByteHash: "raw", normalizedTextHash: "text")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try ledger.saveItem(.init(id: "item", jobID: "job", sourceID: "source", sourceIdentity: note.sourceIdentity, title: note.title, status: .creatingSession, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, metadata: ["imported_note_payload": try encoder.encode(note).base64EncodedString()]))
        _ = try chat.createImportedNoteSession(id: "note-import-session:item", title: note.title, content: note.markdownContent, messageID: "note-import-message:item")
        let service = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: service)

        #expect(try await coordinator.execute(jobID: "job").status == .completed)
        #expect(try ledger.item(id: "item")?.sessionID == "note-import-session:item")
        #expect(try chat.loadRecentSessions(limit: 10).count == 1)
        #expect(try chat.loadRecentSessions(limit: 10).first?.messages.count == 1)
    }

    @Test("Restarts a terminal LLM failure without creating another session")
    func restartsCompletedWithIssues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let store = try SQLiteGraphKernelStore(path: databasePath)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        try ledger.saveSource(.init(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try ledger.saveJob(.init(id: "job", sourceID: "source", status: .completedWithIssues, options: .init(llmMode: .automatic), discoveredCount: 1, importedCount: 1, failedCount: 1))
        let note = ImportedNote(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "Note", markdownContent: "Original", rawByteHash: "raw", normalizedTextHash: "text")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        _ = try chat.createImportedNoteSession(id: "note-import-session:item", title: note.title, content: note.markdownContent, messageID: "note-import-message:item")
        try ledger.saveItem(.init(id: "item", jobID: "job", sourceID: "source", sourceIdentity: note.sourceIdentity, title: note.title, status: .llmFailed, sessionID: "note-import-session:item", rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, attemptCount: 1, errorCode: .llmUnavailable, metadata: ["imported_note_payload": try encoder.encode(note).base64EncodedString()]))
        let service = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: service)

        #expect(try await coordinator.execute(jobID: "job").status == .completed)
        #expect(try ledger.item(id: "item")?.status == .completed)
        #expect(try chat.loadRecentSessions(limit: 10).count == 1)
    }

    @Test("Applies skip, append, and copy duplicate policies independently")
    func duplicatePolicies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let store = try SQLiteGraphKernelStore(path: databasePath)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        let service = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: service)

        for (name, policy, hash, expected) in [
            ("skip", NoteImportDuplicatePolicy.skipUnchanged, "same", NoteImportItemStatus.duplicateUnchanged),
            ("append", .appendUpdate, "changed", .duplicateChanged),
            ("copy", .createCopy, "same", .ready)
        ] {
            let sourceID = "source-\(name)"
            try ledger.saveSource(.init(id: sourceID, kind: .markdownFolder, displayName: name))
            try ledger.saveJob(.init(id: "old-\(name)", sourceID: sourceID, status: .completed, options: .init(llmMode: .disabled), discoveredCount: 1, importedCount: 1))
            let session = try chat.createImportedNoteSession(id: "session-\(name)", title: "Old", content: "Old")
            try ledger.saveItem(.init(id: "old-item-\(name)", jobID: "old-\(name)", sourceID: sourceID, sourceIdentity: "note.md", title: "Old", status: .completed, sessionID: session.id, rawByteHash: "raw", normalizedTextHash: "same"))
            let options = NoteImportOptions(duplicatePolicy: policy, llmMode: .disabled)
            try ledger.saveJob(.init(id: "new-\(name)", sourceID: sourceID, options: options))
            let note = ImportedNote(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "New", markdownContent: "New", rawByteHash: "new", normalizedTextHash: hash)

            _ = try await coordinator.scan(jobID: "new-\(name)", adapter: SingleNoteAdapter(note: note), request: .init(sourceID: sourceID, sourceURL: root, kind: .markdownFolder, options: options))
            let item = try #require(ledger.items(jobID: "new-\(name)").first)
            #expect(item.status == expected)
            if policy == .appendUpdate { #expect(item.sessionID == session.id) }
            if expected == .duplicateUnchanged { #expect(try ledger.job(id: "new-\(name)")?.duplicateCount == 1) }
        }
    }

    @Test("Cleans payload and controlled ENEX staging after successful completion")
    func cleansTerminalStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payloadRoot = root.appendingPathComponent("payloads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let enexRoot = FileManager.default.temporaryDirectory.appendingPathComponent("connor-enex-resources", isDirectory: true)
        try FileManager.default.createDirectory(at: enexRoot, withIntermediateDirectories: true)
        let staged = enexRoot.appendingPathComponent("\(UUID().uuidString)-resource.txt")
        try Data("resource".utf8).write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        let databasePath = root.appendingPathComponent("db.sqlite").path
        let graph = try SQLiteGraphKernelStore(path: databasePath)
        try graph.migrate()
        let chat = AppChatSessionRepository(store: graph)
        let ledger = try AppNoteImportRepository(databasePath: databasePath)
        try ledger.saveSource(.init(id: "source", kind: .evernoteENEX, displayName: "Evernote"))
        let options = NoteImportOptions(importAttachments: false, llmMode: .disabled)
        try ledger.saveJob(.init(id: "job", sourceID: "source", options: options))
        let note = ImportedNote(sourceKind: .evernoteENEX, sourceIdentity: "note", title: "Note", markdownContent: "Body", attachments: [.init(sourcePath: staged.path, displayName: "resource.txt")], rawByteHash: "raw", normalizedTextHash: "text")
        let service = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: service, payloadStore: .init(rootDirectory: payloadRoot))

        _ = try await coordinator.scan(jobID: "job", adapter: SingleNoteAdapter(note: note), request: .init(sourceID: "source", sourceURL: root, kind: .evernoteENEX, options: options))
        #expect(FileManager.default.fileExists(atPath: payloadRoot.appendingPathComponent("job").path))
        #expect(try await coordinator.execute(jobID: "job").status == .completed)
        #expect(!FileManager.default.fileExists(atPath: payloadRoot.appendingPathComponent("job").path))
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}
