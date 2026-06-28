import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Tool Contract Tests")
struct MemoryOSBackgroundToolContractTests {
    @Test func l1WorkerRequestIncludesSearchAndReadProvenanceTools() throws {
        let draft = MemoryOSL1UnifiedProjectionJobDraft(
            id: "job-l1-tools",
            captureEventIDs: ["cap-1"],
            provenanceObjectIDs: ["prov-1"],
            sourceSpanIDs: ["span-1"],
            prompt: "Extract L2 facts."
        )
        let executor = ToolRecordingMemoryOSBackgroundExecutor(response: MemoryOSBackgroundModelResponse(rawArtifactJSON: "{}"))

        _ = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)

        let request = try #require(executor.requests.first)
        let toolNames = request.availableTools.map(\.name)
        #expect(toolNames.contains("memory_os_search"))
        #expect(toolNames.contains("memory_os_read_provenance"))
        #expect(toolNames.contains("memory_os_expand_l4"))
        #expect(request.prompt.contains("Available tools"))
        #expect(request.prompt.contains("memory_os_search"))
        #expect(request.prompt.contains("memory_os_read_provenance"))
        #expect(request.prompt.contains("Must use memory_os_search before deciding whether emitted L2 facts are new, duplicates, or refinements"))
        #expect(request.prompt.contains("Record search-backed judgment"))
    }

    @Test func toolDescriptorsCarrySchemasAndUsagePolicies() throws {
        let tools = MemoryOSBackgroundToolCatalog.l2ToKnowledgeTools()
        let readRecord = try #require(tools.first { $0.name == "memory_os_read_record" })
        #expect(readRecord.description.contains("full Memory OS record"))
        #expect(readRecord.inputSchemaJSON.contains("layer"))
        #expect(readRecord.inputSchemaJSON.contains("recordID"))
        #expect(readRecord.usagePolicy.contains("summary-level context is insufficient"))
    }
}

private final class ToolRecordingMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    var requests: [MemoryOSBackgroundModelRequest] = []
    let response: MemoryOSBackgroundModelResponse

    init(response: MemoryOSBackgroundModelResponse) {
        self.response = response
    }

    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        requests.append(request)
        return response
    }
}
