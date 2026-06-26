import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l1UnifiedProjectionWorkerBuildsModelRequestFromJobDraft() throws {
    let draft = MemoryOSL1UnifiedProjectionJobDraft(
        id: "job-l1",
        captureEventIDs: ["capture-1", "capture-2"],
        provenanceObjectIDs: ["prov-1", "prov-2"],
        sourceSpanIDs: ["span-1"],
        prompt: "Perform L1 unified projection into MemoryOSL1UnifiedProjectionOutput.",
        metadata: ["event_count": "2"]
    )
    let executor = RecordingMemoryOSBackgroundExecutor(response: MemoryOSBackgroundModelResponse(
        rawArtifactJSON: "{\"operationalEntities\":[],\"operationalStatements\":[],\"evidenceSpans\":[],\"knowledgeCandidates\":[],\"conceptEntities\":[],\"conceptRelations\":[],\"promotionDecisions\":[]}",
        metadata: ["model": "mock"]
    ))

    let result = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)

    #expect(executor.requests.count == 1)
    let request = try #require(executor.requests.first)
    #expect(request.jobID == "job-l1")
    #expect(request.kind == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
    #expect(request.schemaName == "MemoryOSL1UnifiedProjectionOutput")
    #expect(request.artifactType == "memory_os_l1_unified_projection")
    #expect(request.prompt.contains("capture-1"))
    #expect(request.prompt.contains("MemoryOSL1UnifiedProjectionOutput"))
    #expect(request.prompt.contains("L2 operational facts") || request.prompt.contains("L2 operational"))
    #expect(request.prompt.contains("L3 reusable knowledge candidates"))
    #expect(request.prompt.contains("stable L4 entity/concept projections"))
    #expect(result.schemaName == "MemoryOSL1UnifiedProjectionOutput")
    #expect(result.artifactType == "memory_os_l1_unified_projection")
    #expect(result.rawArtifactJSON.contains("operationalEntities"))
}

@Test func l2ToKnowledgeWorkerBuildsModelRequestWithRetrievalInstructions() throws {
    let draft = MemoryOSL2ToKnowledgeJobDraft(
        id: "job-l2",
        statementIDs: ["stmt-1"],
        evidenceSpanIDs: ["span-1"],
        prompt: "Use the four knowledge filters and search L2, L3 and L4 before outputting MemoryOSKnowledgeExtractionOutput.",
        metadata: ["statement_count": "1"]
    )
    let executor = RecordingMemoryOSBackgroundExecutor(response: MemoryOSBackgroundModelResponse(
        rawArtifactJSON: "{\"knowledgeCandidates\":[],\"conceptEntities\":[],\"conceptRelations\":[]}",
        metadata: ["model": "mock"]
    ))

    let result = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)

    #expect(executor.requests.count == 1)
    let request = try #require(executor.requests.first)
    #expect(request.jobID == "job-l2")
    #expect(request.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
    #expect(request.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(request.artifactType == "memory_os_knowledge_extraction")
    #expect(request.prompt.contains("four knowledge filters"))
    #expect(request.prompt.contains("L2, L3 and L4") || request.prompt.contains("L2/L3/L4"))
    #expect(request.prompt.contains("depth") || request.prompt.contains("L4"))
    #expect(result.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(result.artifactType == "memory_os_knowledge_extraction")
}

private final class RecordingMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
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
