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

    @Test func kernelRequestEncodesStructuredQueriesWithoutBreakingLegacyQuery() throws {
        let request = MemoryOSSearchKernelRequest(
            query: "Annie Friend",
            queries: ["Annie", "Friend"],
            layers: [.l1, .l2],
            limit: 20
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["query"] as? String == "Annie Friend")
        #expect(object["queries"] as? [String] == ["Annie", "Friend"])
    }
}
