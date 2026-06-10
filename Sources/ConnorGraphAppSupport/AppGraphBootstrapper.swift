import Foundation
import ConnorGraphStore

public struct AppGraphBootstrapper: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func bootstrapStore() throws -> SQLiteGraphKernelStore {
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        try store.seedBaseOntology(graphID: "default")
        return store
    }
}
