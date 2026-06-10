import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppGraphState: Sendable, Equatable {
    public var entities: [GraphEntity]
    public var statements: [GraphStatement]
    public var episodes: [GraphEpisodeV3]
    public var observeLogEntries: [ObserveLogEntry]

    public init(snapshot: GraphStoreSnapshot) {
        self.entities = snapshot.entities
        self.statements = snapshot.statements
        self.episodes = snapshot.episodes
        self.observeLogEntries = snapshot.observeLogEntries
    }
}

public struct AppGraphRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var graphEntityLimit: Int
    public var graphStatementLimit: Int
    public var graphEpisodeLimit: Int
    public var observeLogLimit: Int
    public var graphID: String

    public init(
        store: SQLiteGraphKernelStore,
        graphEntityLimit: Int = 1_000,
        graphStatementLimit: Int = 2_000,
        graphEpisodeLimit: Int = 1_000,
        observeLogLimit: Int = 200,
        graphID: String = "default"
    ) {
        self.store = store
        self.graphEntityLimit = graphEntityLimit
        self.graphStatementLimit = graphStatementLimit
        self.graphEpisodeLimit = graphEpisodeLimit
        self.observeLogLimit = observeLogLimit
        self.graphID = graphID
    }

    public static func bootstrapLive() throws -> AppGraphRepository {
        try bootstrap(paths: .live())
    }

    public static func bootstrap(paths: AppStoragePaths) throws -> AppGraphRepository {
        let bootstrapper = AppGraphBootstrapper(paths: paths)
        return try AppGraphRepository(store: bootstrapper.bootstrapStore())
    }

    public func loadSnapshot() throws -> GraphStoreSnapshot {
        GraphStoreSnapshot(
            entities: Array(try store.entities(graphID: graphID).prefix(graphEntityLimit)),
            statements: Array(try store.statements(graphID: graphID).prefix(graphStatementLimit)),
            episodes: [],
            observeLogEntries: []
        )
    }

    public func loadState() throws -> AppGraphState {
        try AppGraphState(snapshot: loadSnapshot())
    }
}
