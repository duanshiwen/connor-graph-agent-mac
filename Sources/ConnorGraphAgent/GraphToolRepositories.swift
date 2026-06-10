import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public protocol GraphRuntimeRepository: Sendable {
    func upsert(episode: GraphEpisodeV3) throws
    func upsert(observeLogEntry entry: ObserveLogEntry) throws
    func upsert(graphWriteCandidate candidate: GraphWriteCandidate) throws
}
