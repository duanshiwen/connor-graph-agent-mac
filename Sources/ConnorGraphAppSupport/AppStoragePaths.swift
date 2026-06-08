import Foundation

public struct AppStoragePaths: Sendable, Equatable {
    public var applicationSupportDirectory: URL
    public var databaseURL: URL

    public init(applicationSupportDirectory: URL, databaseURL: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.databaseURL = databaseURL
    }

    public static func live(fileManager: FileManager = .default) throws -> AppStoragePaths {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return resolving(applicationSupportBaseDirectory: base)
    }

    public static func resolving(applicationSupportBaseDirectory: URL) -> AppStoragePaths {
        let directory = applicationSupportBaseDirectory.appendingPathComponent("ConnorGraphAgent", isDirectory: true)
        return AppStoragePaths(
            applicationSupportDirectory: directory,
            databaseURL: directory.appendingPathComponent("connor-graph.sqlite")
        )
    }
}
