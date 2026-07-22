import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Tool Contract Tests")
struct MemoryOSBackgroundToolContractTests {
    @Test func l1WorkerRequestIncludesReadAndWriteTools() throws {
        let draft = MemoryOSL1UnifiedProjectionJobDraft(
            id: "job-l1-tools",
            captureEventIDs: ["cap-1"],
            provenanceObjectIDs: ["prov-1"],
            sourceSpanIDs: ["span-1"],
            prompt: "Process L1 cached events."
        )
        let executor = ToolRecordingMemoryOSBackgroundExecutor(response: MemoryOSBackgroundModelResponse(rawArtifactJSON: "{}"))

        _ = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)

        let request = try #require(executor.requests.first)
        let toolNames = request.availableTools.map(\.name)
        // Read tools
        #expect(toolNames.contains("memory_os_recent_context"))
        #expect(toolNames.contains("memory_os_knowledge_context"))
        #expect(toolNames.contains("memory_os_read_provenance"))
        #expect(toolNames.contains("memory_os_expand_l4"))
        // Write tools
        #expect(toolNames.contains("memory_os_l2_update_entities"))
        #expect(toolNames.contains("memory_os_update_current_user_profile"))
        #expect(toolNames.contains("memory_os_l3_update_beliefs"))
        #expect(toolNames.contains("memory_os_l4_update_entities"))
        #expect(request.prompt.contains("Available tools"))
        #expect(request.prompt.contains("memory_os_recent_context"))
        #expect(request.prompt.contains("memory_os_knowledge_context"))
        #expect(request.prompt.contains("memory_os_l2_update_entities"))
        #expect(request.prompt.contains("memory_os_update_current_user_profile"))
    }

    @Test func toolDescriptorsCarrySchemasAndUsagePolicies() throws {
        let tools = MemoryOSBackgroundToolCatalog.l2ToKnowledgeTools()
        let readRecord = try #require(tools.first { $0.name == "memory_os_read_record" })
        #expect(readRecord.description.contains("full Memory OS record"))
        #expect(readRecord.inputSchemaJSON.contains("layer"))
        #expect(readRecord.inputSchemaJSON.contains("recordID"))
        #expect(readRecord.usagePolicy.contains("summary-level context is insufficient"))
        let recent = try #require(tools.first { $0.name == "memory_os_recent_context" })
        #expect(recent.inputSchemaJSON.contains("startDate"))
        #expect(recent.inputSchemaJSON.contains("empty means all records in range"))
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
