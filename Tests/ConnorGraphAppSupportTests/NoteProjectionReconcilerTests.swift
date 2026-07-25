import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Test func noteProjectionReconcilerBackfillsOnlyPersistedNoteFirstMessages() async throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    try store.upsertSession(AgentSession(
        id: "historical-note", title: "History",
        messages: [AgentMessage(id: "source", role: .user, content: "原始正文"), AgentMessage(role: .assistant, content: "AI summary")],
        governance: governance
    ))
    try store.upsertSession(AgentSession(id: "chat", messages: [AgentMessage(role: .user, content: "not a note")]))

    let repository = AppNoteRepository(store: store)
    let result = await NoteProjectionReconciler(repository: repository, batchSize: 1).reconcile(maxBatches: 4)

    #expect(result.projected == 1)
    #expect(try repository.note(sessionID: "historical-note")?.body == "原始正文")
    #expect(try repository.note(sessionID: "chat") == nil)
    let second = await NoteProjectionReconciler(repository: repository).reconcile()
    #expect(second.projected == 0)
}

@Test func noteProjectionClaimsArePersistentAndExpireSafely() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppNoteRepository(store: store)

    #expect(try repository.claimProjection(sessionID: "session", owner: "worker-a", leaseDuration: 300))
    #expect(try !repository.claimProjection(sessionID: "session", owner: "worker-b", leaseDuration: 300))
    try repository.releaseProjection(sessionID: "session", owner: "worker-a")
    #expect(try repository.claimProjection(sessionID: "session", owner: "worker-b", leaseDuration: 300))
}
