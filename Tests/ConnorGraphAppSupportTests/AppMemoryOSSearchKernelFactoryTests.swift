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
}
