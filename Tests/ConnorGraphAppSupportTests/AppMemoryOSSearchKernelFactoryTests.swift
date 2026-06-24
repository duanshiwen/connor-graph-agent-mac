import Foundation
import Testing
@testable import ConnorGraphAppSupport

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
}
