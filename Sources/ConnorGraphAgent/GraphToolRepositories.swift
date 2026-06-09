import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public protocol GraphRuntimeRepository: Sendable {
    func upsert(episode: GraphEpisode) throws
    func upsert(observeLogEntry entry: ObserveLogEntry) throws
    func upsert(graphWriteCandidate candidate: GraphWriteCandidate) throws
}
