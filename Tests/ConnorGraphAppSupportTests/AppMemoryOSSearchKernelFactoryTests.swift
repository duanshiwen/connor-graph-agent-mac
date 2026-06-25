import Foundation
import Testing
@testable import ConnorGraphAppSupport
@testable import ConnorGraphStore

@Suite("App Memory OS Search Kernel Factory Tests")
struct AppMemoryOSSearchKernelFactoryTests {
    @Test func candidateLibraryURLsIncludeRepositoryFallback() {
        let candidates = AppMemoryOSSearchKernelFactory.candidateLibraryURLs(fileManager: .default, bundle: .main)
        #expect(candidates.contains { $0.path.hasSuffix("SearchKernel/target/release/libconnor_memory_search_kernel.dylib") })
        #expect(Set(candidates.map { $0.standardizedFileURL.path }).count == candidates.count)
    }

    @Test func resolveLibraryURLFindsBuiltReleaseKernel() throws {
        let url = try AppMemoryOSSearchKernelFactory.resolveLibraryURL(fileManager: .default, bundle: .main)
        #expect(url.lastPathComponent == "libconnor_memory_search_kernel.dylib")
    }

    @Test func healthReportMarksMissingIndexAsDegraded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()

        let report = AppMemoryOSSearchKernelFactory.healthReport(paths: paths)
        #expect(report.status == .degraded)
        #expect(report.checks["database_exists"] == true)
        #expect(report.checks["connor_meta_exists"] == false)
    }

    @Test func makeLiveIfHealthyReturnsNilForStaleSourceFingerprint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-stale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()
        let indexDirectory = paths.graphDirectory
            .appendingPathComponent("search-index", isDirectory: true)
            .appendingPathComponent("memory-os-tantivy", isDirectory: true)
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        try AppMemoryOSSearchKernelFactory.writeMeta(indexDirectory: indexDirectory, databaseURL: paths.memoryOSDatabaseURL, documentCount: 1)
        try "stale".write(to: paths.memoryOSDatabaseURL, atomically: true, encoding: .utf8)

        let staleReport = AppMemoryOSSearchKernelFactory.healthReport(paths: paths)
        #expect(staleReport.checks["source_database_current"] == false)
        #expect(try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: paths) == nil)
        let unchangedReport = AppMemoryOSSearchKernelFactory.healthReport(paths: paths)
        #expect(unchangedReport.status == .degraded)
    }

    @Test func rebuildLiveIndexRepairsStaleSourceFingerprint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-repair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()

        _ = try AppMemoryOSSearchKernelFactory.rebuildLiveIndex(paths: paths)
        let repairedReport = AppMemoryOSSearchKernelFactory.healthReport(paths: paths)
        #expect(repairedReport.status == .healthy)
        #expect(repairedReport.checks["source_database_current"] == true)
    }
}
