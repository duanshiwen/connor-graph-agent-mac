import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Tool Runtime Tests")
struct MemoryOSBackgroundToolRuntimeTests {
    @Test func backgroundToolCallTypesRoundTripJSON() throws {
        let call = MemoryOSBackgroundToolCall(id: "call-1", name: "memory_os_search", argumentsJSON: #"{"query":"prompt","layers":["L2"]}"#)
        let encodedCall = try JSONEncoder().encode(call)
        let decodedCall = try JSONDecoder().decode(MemoryOSBackgroundToolCall.self, from: encodedCall)
        #expect(decodedCall == call)

        let result = MemoryOSBackgroundToolResult(callID: "call-1", name: "memory_os_search", contentJSON: #"{"hits":[]}"#, contentText: "No hits", citations: ["stmt-1"])
        let encodedResult = try JSONEncoder().encode(result)
        let decodedResult = try JSONDecoder().decode(MemoryOSBackgroundToolResult.self, from: encodedResult)
        #expect(decodedResult == result)
    }

    @Test func workerPreservesExecutorToolTraceMetadata() throws {
        let draft = MemoryOSL1ToL2JobDraft(id: "job-tool-trace", captureEventIDs: ["cap-1"], provenanceObjectIDs: ["prov-1"], sourceSpanIDs: ["span-1"], prompt: "Extract facts.", metadata: ["event_count": "1"])
        let executor = ToolTraceExecutor(response: MemoryOSBackgroundModelResponse(rawArtifactJSON: "{}", metadata: ["tool_trace_count": "2", "tool_trace_ids": "call-1,call-2"]))

        let result = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)

        #expect(result.metadata["event_count"] == "1")
        #expect(result.metadata["tool_trace_count"] == "2")
        #expect(result.metadata["tool_trace_ids"] == "call-1,call-2")
    }
}

private final class ToolTraceExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    let response: MemoryOSBackgroundModelResponse
    init(response: MemoryOSBackgroundModelResponse) { self.response = response }
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse { response }
}
