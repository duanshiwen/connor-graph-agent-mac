import Testing
import Foundation
@testable import ConnorGraphSearch

@Suite("Memory OS Search Kernel Path Tests")
struct MemoryOSSearchKernelPathTests {
    @Test func defaultIndexDirectoryLivesUnderGraphSearchIndex() {
        let graph = URL(fileURLWithPath: "/Users/example/Library/Application Support/Connor/graph", isDirectory: true)
        let index = MemoryOSSearchKernelPaths.defaultIndexDirectory(graphDirectory: graph)
        #expect(index.path == "/Users/example/Library/Application Support/Connor/graph/search-index/memory-os-tantivy")
    }
}
