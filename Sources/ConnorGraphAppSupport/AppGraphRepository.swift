import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphImport

public struct AppGraphState: Sendable, Equatable {
    public var nodes: [GraphNode]
    public var edges: [SemanticEdge]
    public var observeLogEntries: [ObserveLogEntry]

    public init(snapshot: GraphStoreSnapshot) {
        self.nodes = snapshot.nodes
        self.edges = snapshot.edges
        self.observeLogEntries = snapshot.observeLogEntries
    }

    public static func == (lhs: AppGraphState, rhs: AppGraphState) -> Bool {
        lhs.nodes == rhs.nodes &&
        lhs.edges == rhs.edges &&
        lhs.observeLogEntries == rhs.observeLogEntries
    }
}

public struct AppGraphRepository: @unchecked Sendable {
    public let store: SQLiteGraphStore
    public var observeLogLimit: Int

    public init(store: SQLiteGraphStore, observeLogLimit: Int = 200) {
        self.store = store
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
        try store.snapshot(observeLogLimit: observeLogLimit)
    }

    public func loadState() throws -> AppGraphState {
        try AppGraphState(snapshot: loadSnapshot())
    }

    @discardableResult
    public func importKnowledgeDirectory(_ root: URL) throws -> LegacyDirectoryImportReport {
        let importer = LegacyKnowledgeDirectoryImporter(store: store)
        return try importer.importDirectory(root)
    }

    @discardableResult
    public func importLegacyKnowledge(from directory: URL) throws -> LegacyDirectoryImportReport {
        try importKnowledgeDirectory(directory)
    }

    @discardableResult
    public func importReadOnlyKnowledge(from directory: URL) throws -> AppImportReport {
        AppImportReport(try importKnowledgeDirectory(directory))
    }
}
