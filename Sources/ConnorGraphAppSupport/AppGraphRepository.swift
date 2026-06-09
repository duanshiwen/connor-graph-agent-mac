import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppGraphState: Sendable, Equatable {
    public var graphNodes: [GraphNodeV2]
    public var graphFacts: [GraphFact]
    public var graphEpisodes: [GraphEpisode]
    public var observeLogEntries: [ObserveLogEntry]

    public init(snapshot: GraphStoreSnapshot) {
        self.graphNodes = snapshot.graphNodes
        self.graphFacts = snapshot.graphFacts
        self.graphEpisodes = snapshot.graphEpisodes
        self.observeLogEntries = snapshot.observeLogEntries
    }
}

public struct AppGraphRepository: @unchecked Sendable {
    public let store: SQLiteGraphStore
    public var graphNodeLimit: Int
    public var graphFactLimit: Int
    public var graphEpisodeLimit: Int
    public var observeLogLimit: Int

    public init(
        store: SQLiteGraphStore,
        graphNodeLimit: Int = 1_000,
        graphFactLimit: Int = 2_000,
        graphEpisodeLimit: Int = 1_000,
        observeLogLimit: Int = 200
    ) {
        self.store = store
        self.graphNodeLimit = graphNodeLimit
        self.graphFactLimit = graphFactLimit
        self.graphEpisodeLimit = graphEpisodeLimit
        self.observeLogLimit = observeLogLimit
    }

    public static func bootstrapLive() throws -> AppGraphRepository {
        try bootstrap(paths: .live())
    }

    public static func bootstrap(paths: AppStoragePaths) throws -> AppGraphRepository {
        let bootstrapper = AppGraphBootstrapper(paths: paths)
        return try AppGraphRepository(store: bootstrapper.bootstrapStore())
    }

    public func loadSnapshot() throws -> GraphStoreSnapshot {
        try store.snapshot(
            graphNodeLimit: graphNodeLimit,
            graphFactLimit: graphFactLimit,
            graphEpisodeLimit: graphEpisodeLimit,
            observeLogLimit: observeLogLimit
        )
    }

    public func loadState() throws -> AppGraphState {
        try AppGraphState(snapshot: loadSnapshot())
    }
}
