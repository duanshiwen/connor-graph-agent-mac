import Foundation
import ConnorGraphStore

public struct AppGraphBootstrapper: Sendable {
    public var paths: AppStoragePaths

    public init(paths: AppStoragePaths) {
        self.paths = paths
    }

    public func bootstrapStore() throws -> SQLiteGraphStore {
        try FileManager.default.createDirectory(
            at: paths.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let store = try SQLiteGraphStore(path: paths.databaseURL.path)
        try store.migrate()
        return store
    }
}
