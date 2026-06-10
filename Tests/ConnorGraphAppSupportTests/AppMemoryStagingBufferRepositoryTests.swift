import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryAppMemoryStagingDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appMemoryStagingBufferRepositorySavesLoadsListsAndDeletesBuffers() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppMemoryStagingDatabaseURL().path)
    try store.migrate()
    let repository = AppMemoryStagingBufferRepository(store: store)
    let active = MemoryStagingBuffer(id: "buffer-active", sessionID: "session-active", tokenEstimate: 12)
    let drained = MemoryStagingBuffer(id: "buffer-drained", sessionID: "session-drained", status: .drained)

    try repository.saveBuffer(active, updatedAt: Date(timeIntervalSince1970: 1))
    try repository.saveBuffer(drained, updatedAt: Date(timeIntervalSince1970: 2))

    #expect(try repository.loadBuffer(sessionID: "session-active") == active)
    #expect(try repository.loadBuffer(id: "buffer-drained") == drained)
    #expect(try repository.loadBuffers(status: .active).map(\.id) == ["buffer-active"])

    try repository.deleteBuffer(sessionID: "session-active")
    try repository.deleteBuffer(id: "buffer-drained")

    #expect(try repository.loadBuffers().isEmpty)
}
