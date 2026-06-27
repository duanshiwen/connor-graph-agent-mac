import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Agent Model Adapter Tests")
struct MemoryOSBackgroundAgentModelAdapterTests {
    @Test func agentModelBackgroundToolLoopModelMapsRequestsAndResponses() async throws {
        let recorder = AgentModelRequestRecorder()
        let provider = AnyAgentModelProvider(
            modelID: "debug-model",
            capabilities: AgentModelCapabilities(
                supportsStreaming: false,
                supportsToolCalling: true,
                supportsParallelToolCalls: false,
                supportsStructuredOutput: false,
                supportsVision: false
            )
        ) { request in
            await recorder.record(request)
            return AgentModelResponse(
                text: "I need to search.",
                toolCalls: [AgentToolCall(id: "call-1", name: "memory_os_search", argumentsJSON: "{\"query\":\"Connor\",\"limit\":5}")],
                usage: AgentModelUsage(promptTokens: 11, completionTokens: 7),
                finishReason: .toolCalls,
                rawResponseJSON: "{\"id\":\"resp-1\"}",
                providerMetadata: AgentModelProviderMetadata(providerID: "test-provider", responseID: "resp-1", reasoningEncryptedContentPresent: false)
            )
        }
        let model = AgentModelBackgroundToolLoopModel(provider: provider)
        let request = MemoryOSBackgroundLoopModelRequest(
            runID: "run-1",
            job: MemoryOSBackgroundModelRequest(
                jobID: "job-1",
                kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
                schemaName: "schema",
                artifactType: "artifact",
                prompt: "Prompt",
                availableTools: []
            ),
            messages: [
                MemoryOSBackgroundLoopMessage(id: "msg-1", role: .user, content: "Prompt"),
                MemoryOSBackgroundLoopMessage(id: "msg-2", role: .tool, content: "Tool result", toolCallID: "call-0", toolName: "memory_os_search")
            ],
            availableTools: [
                MemoryOSBackgroundToolDescriptor(
                    name: "memory_os_search",
                    description: "Search Memory OS.",
                    inputSchemaJSON: "{\"query\":\"string\",\"limit\":\"number\"}",
                    usagePolicy: "Use before emitting knowledge."
                )
            ]
        )

        let response = try model.complete(request)
        let agentRequest = try #require(await recorder.lastRequest)

        #expect(model.modelID == "debug-model")
        #expect(agentRequest.messages.count == 2)
        #expect(agentRequest.messages[0].role == .user)
        #expect(agentRequest.messages[0].content == "Prompt")
        #expect(agentRequest.messages[1].role == .tool)
        #expect(agentRequest.messages[1].toolCallID == "call-0")
        #expect(agentRequest.tools.count == 1)
        #expect(agentRequest.tools[0].name == "memory_os_search")
        #expect(agentRequest.tools[0].description.contains("Usage policy"))
        #expect(response.assistantText == "I need to search.")
        #expect(response.toolCalls == [MemoryOSBackgroundToolCall(id: "call-1", name: "memory_os_search", argumentsJSON: "{\"query\":\"Connor\",\"limit\":5}")])
        #expect(response.finalArtifactJSON == nil)
        #expect(response.metadata["model_id"] == "debug-model")
        #expect(response.metadata["model_supports_tool_calling"] == "true")
        #expect(response.metadata["provider_id"] == "test-provider")
        #expect(response.metadata["provider_response_id"] == "resp-1")
        #expect(response.metadata["total_tokens"] == "18")
    }

    @Test func agentModelBackgroundToolLoopModelExtractsFinalArtifactWhenNoToolCalls() throws {
        let provider = AnyAgentModelProvider(modelID: "debug-model") { _ in
            AgentModelResponse(text: "{\"artifactType\":\"memory.l1.unified_projection\"}", toolCalls: [])
        }
        let model = AgentModelBackgroundToolLoopModel(provider: provider)
        let response = try model.complete(MemoryOSBackgroundLoopModelRequest(
            runID: "run-1",
            job: MemoryOSBackgroundModelRequest(jobID: "job-1", kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, schemaName: "schema", artifactType: "artifact", prompt: "Prompt"),
            messages: [MemoryOSBackgroundLoopMessage(role: .user, content: "Prompt")],
            availableTools: []
        ))

        #expect(response.finalArtifactJSON == "{\"artifactType\":\"memory.l1.unified_projection\"}")
    }
}

private actor AgentModelRequestRecorder {
    var lastRequest: AgentModelRequest?

    func record(_ request: AgentModelRequest) {
        lastRequest = request
    }
}
