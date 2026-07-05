import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Activity Timeline Cache Writer Tests")
struct ActivityTimelineCacheWriterTests {
    @Test func scheduleSaveDebouncesMultipleUpdatesAndWritesLatestTimeline() async throws {
        let persistor = RecordingTimelinePersistor()
        let writer = ActivityTimelineCacheWriter(persistor: persistor, debounceNanoseconds: 20_000_000)
        let sessionID = "session-1"

        await writer.scheduleSave(sessionID: sessionID, timeline: [event("one")])
        await writer.scheduleSave(sessionID: sessionID, timeline: [event("one"), event("two")])
        try await Task.sleep(nanoseconds: 80_000_000)

        let writes = persistor.writes
        #expect(writes.count == 1)
        #expect(writes.first?.sessionID == sessionID)
        #expect(writes.first?.timeline.map(\.id) == ["one", "two"])
    }

    @Test func flushWritesLatestTimelineImmediately() async throws {
        let persistor = RecordingTimelinePersistor()
        let writer = ActivityTimelineCacheWriter(persistor: persistor, debounceNanoseconds: 1_000_000_000)
        let sessionID = "session-2"

        await writer.scheduleSave(sessionID: sessionID, timeline: [event("draft")])
        try await writer.flush(sessionID: sessionID)

        let writes = persistor.writes
        #expect(writes.count == 1)
        #expect(writes.first?.timeline.map(\.id) == ["draft"])
    }

    private func event(_ id: String) -> AgentEventPresentation {
        AgentEventPresentation(id: id, kind: "toolFinished", title: id, detail: id, severity: .success, runID: "run", sessionID: "session")
    }
}

private final class RecordingTimelinePersistor: ActivityTimelineCachePersisting, @unchecked Sendable {
    struct Write: Sendable, Equatable {
        var sessionID: String
        var timeline: [AgentEventPresentation]
    }

    private let lock = NSLock()
    private var protectedWrites: [Write] = []

    var writes: [Write] {
        lock.lock()
        defer { lock.unlock() }
        return protectedWrites
    }

    func saveActivityTimelineCache(sessionID: String, timeline: [AgentEventPresentation]) throws {
        lock.lock()
        protectedWrites.append(Write(sessionID: sessionID, timeline: timeline))
        lock.unlock()
    }
}
