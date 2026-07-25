import Foundation
import ConnorGraphCore

public struct NoteProjectionReconciliationResult: Sendable, Equatable {
    public var projected: Int
    public var removed: Int
    public var failed: Int
    public var hasMore: Bool
}

public actor NoteProjectionReconciler {
    private let repository: AppNoteRepository
    private let projection: AppNoteProjectionService
    private let batchSize: Int
    private let bodyBudget: Int
    private let decoder: JSONDecoder

    public init(repository: AppNoteRepository, batchSize: Int = 25, bodyBudget: Int = 1_000_000) {
        self.repository = repository
        self.projection = AppNoteProjectionService(repository: repository)
        self.batchSize = min(max(batchSize, 1), 100)
        self.bodyBudget = max(bodyBudget, 1)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func reconcile(maxBatches: Int = 8) async -> NoteProjectionReconciliationResult {
        var projected = 0
        var removed = 0
        var failed = 0
        var cursor: String?
        var hasMore = false
        let owner = "note-reconcile:\(UUID().uuidString)"

        for sessionID in (try? repository.orphanedSessionIDs(limit: batchSize)) ?? [] {
            do { try repository.delete(sessionID: sessionID); removed += 1 } catch { failed += 1 }
        }

        for _ in 0..<max(maxBatches, 1) {
            guard !Task.isCancelled else { break }
            let candidates: [NoteProjectionCandidate]
            do { candidates = try repository.projectionCandidates(afterSessionID: cursor, limit: batchSize) }
            catch { failed += 1; break }
            if candidates.isEmpty { hasMore = false; break }
            hasMore = candidates.count == batchSize
            var consumedCharacters = 0
            for candidate in candidates {
                guard !Task.isCancelled else { hasMore = true; break }
                if consumedCharacters > 0 && consumedCharacters + candidate.messageJSON.count > bodyBudget {
                    hasMore = true
                    break
                }
                consumedCharacters += candidate.messageJSON.count
                cursor = candidate.sessionID
                guard (try? repository.claimProjection(sessionID: candidate.sessionID, owner: owner)) == true else { continue }
                defer { try? repository.releaseProjection(sessionID: candidate.sessionID, owner: owner) }
                do {
                    let message = try decoder.decode(AgentMessage.self, from: Data(candidate.messageJSON.utf8))
                    var governance = AgentSessionGovernanceMetadata.default
                    governance.kind = .note
                    let session = AgentSession(
                        id: candidate.sessionID, title: candidate.title, messages: [message],
                        createdAt: candidate.createdAt, updatedAt: candidate.updatedAt, governance: governance
                    )
                    try projection.synchronize(session: session, origin: .native)
                    projected += 1
                } catch {
                    failed += 1
                }
            }
            await Task.yield()
        }
        return NoteProjectionReconciliationResult(projected: projected, removed: removed, failed: failed, hasMore: hasMore)
    }
}
