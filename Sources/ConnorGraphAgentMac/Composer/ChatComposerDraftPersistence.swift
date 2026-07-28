import Foundation
import ConnorGraphAppSupport

private struct ChatComposerDraftRecord: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var sessionID: String
    var text: String
    var updatedAt: Date
}

struct ChatComposerDraftRepository: Sendable {
    let storagePaths: AppStoragePaths

    func load(sessionID: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(sessionID: sessionID)),
              let record = try? decoder.decode(ChatComposerDraftRecord.self, from: data),
              record.schemaVersion == 1,
              record.sessionID == sessionID else { return nil }
        return record.text
    }

    func save(_ draft: String, sessionID: String, now: Date = Date()) throws {
        let url = fileURL(sessionID: sessionID)
        if draft.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = ChatComposerDraftRecord(
            schemaVersion: 1,
            sessionID: sessionID,
            text: draft,
            updatedAt: now
        )
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    func remove(sessionID: String) {
        try? FileManager.default.removeItem(at: fileURL(sessionID: sessionID))
    }

    private func fileURL(sessionID: String) -> URL {
        storagePaths.sessionArtifactDirectories(sessionID: sessionID).state
            .appendingPathComponent("composer-draft.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class ChatComposerDraftPersistence: @unchecked Sendable {
    private let repository: ChatComposerDraftRepository
    private let queue = DispatchQueue(label: "com.connor.chat-composer-drafts", qos: .utility)
    private let lock = NSLock()
    private var pendingWorkBySessionID: [String: DispatchWorkItem] = [:]
    private var revisionBySessionID: [String: Int] = [:]
    private let saveDelay: TimeInterval

    init(repository: ChatComposerDraftRepository, saveDelay: TimeInterval = 0.3) {
        self.repository = repository
        self.saveDelay = saveDelay
    }

    func load(sessionID: String) -> String? {
        queue.sync { repository.load(sessionID: sessionID) }
    }

    func scheduleSave(_ draft: String, sessionID: String) {
        let work = makeCurrentWork(sessionID: sessionID) { [repository] in
            try? repository.save(draft, sessionID: sessionID)
        }
        queue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    func remove(sessionID: String) {
        invalidatePendingWork(sessionID: sessionID)
        queue.sync {
            repository.remove(sessionID: sessionID)
        }
    }

    func flush(_ draftsBySessionID: [String: String]) {
        cancelPendingWork()
        queue.sync {
            for (sessionID, draft) in draftsBySessionID {
                try? repository.save(draft, sessionID: sessionID)
            }
        }
    }

    private func makeCurrentWork(
        sessionID: String,
        operation: @escaping @Sendable () -> Void
    ) -> DispatchWorkItem {
        lock.lock()
        pendingWorkBySessionID[sessionID]?.cancel()
        let revision = (revisionBySessionID[sessionID] ?? 0) + 1
        revisionBySessionID[sessionID] = revision
        let work = DispatchWorkItem { [weak self] in
            guard self?.isCurrent(sessionID: sessionID, revision: revision) == true else { return }
            operation()
        }
        pendingWorkBySessionID[sessionID] = work
        lock.unlock()
        return work
    }

    private func isCurrent(sessionID: String, revision: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return revisionBySessionID[sessionID] == revision
    }

    private func invalidatePendingWork(sessionID: String) {
        lock.lock()
        pendingWorkBySessionID.removeValue(forKey: sessionID)?.cancel()
        revisionBySessionID.removeValue(forKey: sessionID)
        lock.unlock()
    }

    private func cancelPendingWork() {
        lock.lock()
        pendingWorkBySessionID.values.forEach { $0.cancel() }
        pendingWorkBySessionID.removeAll()
        revisionBySessionID.removeAll()
        lock.unlock()
    }
}
