import Foundation

public protocol ActivityTimelineCachePersisting: Sendable {
    func saveActivityTimelineCache(sessionID: String, timeline: [AgentEventPresentation]) throws
}

extension AppChatSessionRepository: ActivityTimelineCachePersisting {}

public actor ActivityTimelineCacheWriter {
    private struct PendingSave: Sendable {
        var timeline: [AgentEventPresentation]
        var task: Task<Void, Never>?
    }

    private let persistor: any ActivityTimelineCachePersisting
    private let debounceNanoseconds: UInt64
    private var pendingSaves: [String: PendingSave] = [:]

    public init(
        persistor: any ActivityTimelineCachePersisting,
        debounceNanoseconds: UInt64 = 350_000_000
    ) {
        self.persistor = persistor
        self.debounceNanoseconds = debounceNanoseconds
    }

    public func scheduleSave(sessionID: String, timeline: [AgentEventPresentation]) {
        pendingSaves[sessionID]?.task?.cancel()
        let task = Task { [debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            try? flush(sessionID: sessionID)
        }
        pendingSaves[sessionID] = PendingSave(timeline: timeline, task: task)
    }

    public func waitForPendingSave(sessionID: String) async {
        let task = pendingSaves[sessionID]?.task
        await task?.value
    }

    public func flush(sessionID: String) throws {
        guard let pending = pendingSaves.removeValue(forKey: sessionID) else { return }
        pending.task?.cancel()
        try persistor.saveActivityTimelineCache(sessionID: sessionID, timeline: pending.timeline)
    }

    public func flushAll() throws {
        let sessionIDs = Array(pendingSaves.keys)
        for sessionID in sessionIDs {
            try flush(sessionID: sessionID)
        }
    }
}
