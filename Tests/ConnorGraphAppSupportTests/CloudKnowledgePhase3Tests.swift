import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Cloud Knowledge Phase 3 Tests")
struct CloudKnowledgePhase3Tests {
    @Test func apiClientUsesV2SnakeCaseContractAndMapsConflict() async throws {
        let transport = CloudKnowledgeHTTPTransport()
        let client = CloudKnowledgeAPIClient(baseURL: URL(string: "https://backend.example")!, transport: transport, credentials: StaticCloudCredential())
        let run = try await client.createPublicationRun(knowledgeBaseID: "kb 1", request: .init(clientRunID: "client-1", expectedBaseSequence: 7))
        #expect(run.id == "run-1")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/v2/knowledge-bases/kb 1/publication-runs")
        #expect(request.url?.absoluteString.contains("/api/v2/knowledge-bases/kb%201/publication-runs") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["client_run_id"] as? String == "client-1")
        #expect(object["expected_base_sequence"] as? Int == 7)
        #expect(object["schema_version"] as? String == "v2")
        await transport.enableConflict()
        await #expect(throws: CloudKnowledgeError.publicationConflict(currentSequence: 9)) { try await client.commit(runID: "run-1") }
    }

    @Test func traceValidatorRejectsMissingIrrelevantAndStaleCoverage() throws {
        let context = CloudKnowledgePublishingContext(knowledgeBaseID: "kb", publicationRunID: "run", ownerUserID: "u", clientRunID: "c")
        let operation = Self.operation(layer: .l3, contextID: "search", terms: ["时序知识"])
        let validator = CloudKnowledgePublishingTraceValidator()
        #expect(throws: CloudKnowledgeError.searchBeforeWriteRequired) { try validator.validate(operation: operation, trace: nil, context: context, currentBaseSequence: 1, currentStagedSequence: 0) }
        let irrelevant = CloudKnowledgeSearchTrace(contextID: "search", knowledgeBaseID: "kb", publicationRunID: "run", channel: .recentContext, queryTerms: ["时序知识"], layers: [.l2], baseSequence: 1, stagedSequence: 0, expiresAt: nil)
        #expect(throws: CloudKnowledgeError.searchContextNotRelevant) { try validator.validate(operation: operation, trace: irrelevant, context: context, currentBaseSequence: 1, currentStagedSequence: 0) }
        let stale = CloudKnowledgeSearchTrace(contextID: "search", knowledgeBaseID: "kb", publicationRunID: "run", channel: .knowledgeContext, queryTerms: ["时序知识"], layers: [.l3], baseSequence: 1, stagedSequence: 0, expiresAt: Date(timeIntervalSince1970: 0))
        #expect(throws: CloudKnowledgeError.searchContextStale) { try validator.validate(operation: operation, trace: stale, context: context, currentBaseSequence: 1, currentStagedSequence: 0) }
    }

    @Test func laterConversationSearchesCombinedViewAndSeesEarlierStagedKnowledge() async throws {
        let api = InMemoryCloudKnowledgeAPI()
        let context = CloudKnowledgePublishingContext(knowledgeBaseID: "kb", publicationRunID: "run", ownerUserID: "u", clientRunID: "client")
        let coordinator = CloudKnowledgePublicationCoordinator(api: api, context: context, run: .init(id: "run", knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: 4))
        let conversations = [CloudKnowledgeLocalConversation(localID: "local-1", title: "一", localPrompt: "raw one"), CloudKnowledgeLocalConversation(localID: "local-2", title: "二", localPrompt: "raw two")]
        try await CloudKnowledgeStagedConversationProcessor().process(conversations, coordinator: coordinator) { conversation, search in
            let response = try await search.search(channel: .knowledgeContext, request: .init(query: "Connor 时序知识", layers: [.l3]))
            if conversation.localID == "local-2" { #expect(response.results.contains { $0.staged }) }
            return [Self.operation(layer: .l3, contextID: response.searchContextID, terms: ["Connor", "时序知识"], payloadText: conversation.title)]
        }
        #expect(await coordinator.processedLocalConversationIDs == ["local-1", "local-2"])
        #expect(await api.searchViews == [.combined, .combined])
        #expect(await api.searchStagedSequences == [0, 1])
        #expect(await api.receivedPayloadTexts == ["一", "二"])
        #expect(await api.receivedRequestBodiesContainRawConversation == false)
    }

    @Test func canonicalSearchFixtureDerivesPresentationWithoutBackendTitleOrText() throws {
        let json = #"{"search_context_id":"sc-1","channel":"knowledge_context","base_sequence":8,"staged_sequence":2,"expires_at":"2026-07-13T10:10:00Z","results":[{"source":"staged","identity_id":"identity-1","revision_id":"revision-1","layer":"L3","kind":"reusable_knowledge","stable_key":"connor-agent","payload":{"title":"Connor Agent","summary":"本地优先 Agent OS"},"score":0.91,"staged_sequence":2},{"source":"committed","identity_id":"identity-2","layer":"L4","kind":"entity","stable_key":"memory-os","payload":{"domain":"knowledge","status":"active"},"score":0.8}]}"#
        let response = try JSONDecoder.cloudContract.decode(CloudKnowledgeSearchResponse.self, from: Data(json.utf8))
        #expect(response.results[0].title == "Connor Agent")
        #expect(response.results[0].text == "本地优先 Agent OS")
        #expect(response.results[0].staged)
        #expect(response.results[0].hints.isEmpty)
        #expect(response.results[1].title == "memory-os")
        #expect(response.results[1].text.contains("knowledge"))
        #expect(response.results[1].staged == false)
    }

    @Test func batcherPreservesOrderAndEnforcesOperationCount() throws {
        let operations = (0..<5).map { Self.operation(layer: .l2, contextID: "s", terms: ["t\($0)"], payloadText: "\($0)") }
        let batches = try CloudKnowledgeBatcher(maximumOperations: 2, maximumEncodedBytes: 100_000).batches(operations)
        #expect(batches.map(\.count) == [2, 2, 1])
        #expect(batches.flatMap { $0 }.map(\.payload["text"]) == operations.map(\.payload["text"]))
    }

    @Test func toolExecutorMapsCandidateDecisionToCanonicalTimelineOperationAndSkipsNoOps() async throws {
        let api = InMemoryCloudKnowledgeAPI()
        let context = CloudKnowledgePublishingContext(knowledgeBaseID: "kb", publicationRunID: "run", ownerUserID: "u", clientRunID: "client")
        let coordinator = CloudKnowledgePublicationCoordinator(api: api, context: context, run: .init(id: "run", knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: 4))
        let executor = CloudKnowledgeToolExecutor(coordinator: coordinator)
        let executionContext = AgentToolExecutionContext(runID: "agent-run", sessionID: "local", groupID: "g", userPrompt: "publish", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
        let search = try await executor.execute(toolName: "cloud_kb_knowledge_context", arguments: try AgentToolArguments(json: #"{"query":"Connor","limit":20}"#), context: executionContext)
        let searchData = try #require(search.contentJSON?.data(using: String.Encoding.utf8)); let response = try JSONDecoder().decode(CloudKnowledgeSearchResponse.self, from: searchData)
        _ = try await executor.execute(toolName: "cloud_kb_l3_update_knowledge", arguments: try AgentToolArguments(json: #"{"search_context_id":"\#(response.searchContextID)","decision":"skip_duplicate","semantic_terms":["Connor"],"payload":{}}"#), context: executionContext)
        #expect(await api.operations.isEmpty)
        _ = try await executor.execute(toolName: "cloud_kb_l3_update_knowledge", arguments: try AgentToolArguments(json: #"{"search_context_id":"\#(response.searchContextID)","decision":"create_new","semantic_terms":["Connor"],"payload":{"kind":"reusable_knowledge","stable_key":"connor","valid_from":"2026-07-13T10:00:00Z","payload":{"title":"Connor"}}}"#), context: executionContext)
        let operation = try #require(await api.operations.first)
        #expect(operation.operationType == "create")
        #expect(operation.targetIdentityID == nil)
        #expect(operation.payload["layer"] == .string("L3"))
        #expect(operation.payload["stable_key"] == .string("connor"))
        #expect(operation.payload["payload"] == .object(["title": .string("Connor")]))
        let encoded = try JSONEncoder.cloudContract.encode(CloudKnowledgeOperationBatchRequest(operations: [operation]))
        let fixture = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let rows = try #require(fixture["operations"] as? [[String: Any]])
        #expect(rows[0]["operation_type"] as? String == "create")
        #expect(rows[0]["layer"] as? String == "L3")
        #expect(rows[0]["decision"] as? String == "create_new")
        #expect((rows[0]["payload"] as? [String: Any])?["stable_key"] as? String == "connor")
        let validationJSON = #"{"valid":false,"issues":[{"code":"invalid_stable_key","message":"bad key","operation_id":"op-1","repairable":true}],"staged_sequence":3}"#
        let validation = try JSONDecoder.cloudContract.decode(CloudKnowledgeValidationResult.self, from: Data(validationJSON.utf8))
        #expect(validation.issues.first?.operationID == "op-1")
        #expect(validation.stagedSequence == 3)
    }

    @Test func promptAndToolSchemasEnforceLocalOnlySearchBeforeWriteBoundary() async throws {
        let prompt = CloudKnowledgePublishingPrompt.instruction
        #expect(prompt.contains("must never be sent to the Connor knowledge backend"))
        #expect(prompt.contains("combined committed + current-run staged view"))
        #expect(prompt.contains("Never invent identity IDs"))
        let api = InMemoryCloudKnowledgeAPI(); let context = CloudKnowledgePublishingContext(knowledgeBaseID: "kb", publicationRunID: "run", ownerUserID: "u", clientRunID: "client")
        let coordinator = CloudKnowledgePublicationCoordinator(api: api, context: context, run: .init(id: "run", knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: 4))
        var registry = AgentToolRegistry(); registry.registerCloudKnowledgePublicationTools(executor: CloudKnowledgeToolExecutor(coordinator: coordinator))
        let names = registry.definitions.map(\.name)
        #expect(names.contains("cloud_kb_recent_context")); #expect(names.contains("cloud_kb_l3_update_knowledge")); #expect(names.contains("cloud_kb_validate_publication"))
        #expect(registry.schemaValidationIssues.isEmpty)
        let write = try #require(registry.definition(named: "cloud_kb_l3_update_knowledge"))
        let schema = write.inputSchema.jsonObject
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties["knowledge_base_id"] == nil); #expect(properties["publication_run_id"] == nil); #expect(properties["owner_user_id"] == nil); #expect(properties["raw_conversation"] == nil)
        let payloadSchema = try #require(properties["payload"] as? [String: Any])
        let payloadProperties = try #require(payloadSchema["properties"] as? [String: Any])
        #expect(payloadProperties["kind"] != nil)
        #expect(payloadProperties["stable_key"] != nil)
        #expect(payloadProperties["valid_from"] != nil)
        #expect(payloadProperties["payload"] != nil)
        #expect(write.description.contains("kind, stable_key, valid_from"))
    }

    @Test func realModelToolLoopSearchesStagesAndSummarizesConversation() async throws {
        let api = InMemoryCloudKnowledgeAPI()
        let scripted = CloudKnowledgeScriptedProvider()
        let provider = AnyAgentModelProvider(
            modelID: "tool-model",
            capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false),
            complete: { request in try await scripted.complete(request) }
        )
        let session = AgentSession(id: "conversation-1", title: "Connor knowledge", messages: [
            AgentMessage(role: .system, content: "MAIN_AGENT_SYSTEM_PROMPT_SENTINEL"),
            AgentMessage(role: .user, content: "Connor 使用结构化知识发布流程。"),
            AgentMessage(role: .assistant, content: "结构化发布需要检索后写入。")
        ])

        let result = try await CloudKnowledgeLLMGenerationRunner().generate(
            session: session,
            knowledgeBaseID: "kb",
            publicationRunID: "run",
            clientRunID: "client",
            api: api,
            provider: provider
        )

        #expect(result.summary == "已完成《Connor knowledge》的知识分析：检索 2 次，处理 1 个知识决策。")
        #expect(await api.operations.count == 1)
        #expect(await api.searchViews == [.combined, .combined])
        #expect(await scripted.requestCount == 3)
        #expect(await scripted.exposedValidationTool == false)
        #expect(await scripted.usedDedicatedExtractionPrompt)
        #expect(await scripted.usedExplicitTerminationContract)
        #expect(await scripted.exposedMainAgentSystemPrompt == false)
        #expect(await api.operations.first?.semanticTerms.contains { $0.caseInsensitiveCompare("connor") == .orderedSame } == true)
    }

    @Test func extractionSourceContainsOnlyUserAndFinalAssistantTurnPairs() throws {
        let session = AgentSession(id: "source-projection", title: "Projection", messages: [
            AgentMessage(role: .system, content: "MAIN_SYSTEM_PROMPT_MUST_NOT_LEAK"),
            AgentMessage(role: .assistant, content: "ORPHAN_ASSISTANT_MUST_NOT_LEAK"),
            AgentMessage(role: .user, content: "FIRST_USER_MESSAGE"),
            AgentMessage(role: .assistant, content: "INTERMEDIATE_ASSISTANT_MUST_NOT_LEAK"),
            AgentMessage(role: .assistant, content: "FIRST_FINAL_RESPONSE"),
            AgentMessage(role: .user, content: "UNFINISHED_USER_MUST_NOT_LEAK")
        ])

        #expect(CloudKnowledgeExtractionPrompt.sourceTurns(session: session) == [
            CloudKnowledgeSourceTurn(userMessage: "FIRST_USER_MESSAGE", assistantFinalResponse: "FIRST_FINAL_RESPONSE")
        ])
        let prompt = CloudKnowledgeExtractionPrompt.sourcePrompt(
            session: session,
            processingTime: Date(timeIntervalSince1970: 0)
        )
        #expect(prompt.contains("\"user_message\" : \"FIRST_USER_MESSAGE\"") || prompt.contains("\"user_message\": \"FIRST_USER_MESSAGE\""))
        #expect(prompt.contains("\"assistant_final_response\" : \"FIRST_FINAL_RESPONSE\"") || prompt.contains("\"assistant_final_response\": \"FIRST_FINAL_RESPONSE\""))
        #expect(!prompt.contains("MAIN_SYSTEM_PROMPT_MUST_NOT_LEAK"))
        #expect(!prompt.contains("ORPHAN_ASSISTANT_MUST_NOT_LEAK"))
        #expect(!prompt.contains("INTERMEDIATE_ASSISTANT_MUST_NOT_LEAK"))
        #expect(!prompt.contains("UNFINISHED_USER_MUST_NOT_LEAK"))
    }

    @Test func writeAssistSearchContextCanDriveL3Write() async throws {
        let api = InMemoryCloudKnowledgeAPI()
        let scripted = CloudKnowledgeWriteAssistProvider()
        let provider = AnyAgentModelProvider(
            modelID: "tool-model",
            capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false),
            complete: { request in try await scripted.complete(request) }
        )
        let session = AgentSession(id: "conversation-write-assist", title: "Answer cache", messages: [
            AgentMessage(role: .user, content: "How should Answer cache refresh?"),
            AgentMessage(role: .assistant, content: "Answer cache uses bounded refresh policies.")
        ])

        _ = try await CloudKnowledgeLLMGenerationRunner().generate(
            session: session,
            knowledgeBaseID: "kb",
            publicationRunID: "run",
            clientRunID: "client",
            api: api,
            provider: provider
        )

        #expect(await api.operations.count == 1)
        #expect(await api.operations.first?.semanticTerms == ["answer cache answer package"])
        #expect(await api.searchViews == [.combined, .combined])
        #expect(await scripted.requestCount == 3)
    }

    @Test func repeatedToolErrorKeepsBoundedDiagnosticForRecovery() {
        let longMessage = String(repeating: "invalid payload ", count: 30)
        let bounded = String(longMessage.prefix(240))
        let error = CloudKnowledgeLLMGenerationError.tooManyToolErrors(lastError: bounded)

        #expect(error.localizedDescription.contains("最后一次错误"))
        #expect(error.localizedDescription.contains(bounded))
        #expect(bounded.count == 240)
    }

    @Test func agentToolErrorsExposeTheirActionableDescription() {
        let error: Error = AgentToolError.invalidArguments("payload requires stable_key")
        let diagnostic = (error as? AgentToolError)?.description ?? error.localizedDescription

        #expect(diagnostic == "Invalid arguments: payload requires stable_key")
    }

    private static func operation(layer: CloudKnowledgeLayer, contextID: String, terms: [String], payloadText: String = "knowledge") -> CloudKnowledgeOperation {
        CloudKnowledgeOperation(operationType: "update", layer: layer, decision: .createNew, searchContextID: contextID, semanticTerms: terms, payload: ["text": .string(payloadText)])
    }
}

private extension JSONEncoder {
    static var cloudContract: JSONEncoder { let value = JSONEncoder(); value.keyEncodingStrategy = .convertToSnakeCase; value.dateEncodingStrategy = .iso8601; return value }
}
private extension JSONDecoder {
    static var cloudContract: JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601
        value.keyDecodingStrategy = .custom { path in
            let raw = path.last?.stringValue ?? ""; let parts = raw.split(separator: "_")
            let transformed = parts.enumerated().map { index, part in index == 0 ? String(part) : (part.lowercased() == "id" ? "ID" : part.prefix(1).uppercased() + part.dropFirst()) }.joined()
            return CloudTestCodingKey(stringValue: transformed)!
        }
        return value
    }
}
private struct CloudTestCodingKey: CodingKey { var stringValue: String; var intValue: Int? = nil; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }

private struct StaticCloudCredential: CloudKnowledgeCredentialProvider { func accessToken() async throws -> String { "token" } }

private actor CloudKnowledgeScriptedProvider {
    var requestCount = 0
    var exposedValidationTool = false
    var usedDedicatedExtractionPrompt = false
    var usedExplicitTerminationContract = false
    var exposedMainAgentSystemPrompt = false

    func complete(_ request: AgentModelRequest) throws -> AgentModelResponse {
        requestCount += 1
        exposedValidationTool = exposedValidationTool || request.tools.contains { $0.name == "cloud_kb_validate_publication" }
        usedDedicatedExtractionPrompt = usedDedicatedExtractionPrompt || request.messages.first?.content.contains("bounded background knowledge-extraction worker") == true
        usedExplicitTerminationContract = usedExplicitTerminationContract || request.messages.first?.content.contains("A successful write is not, by itself, a reason to stop") == true
        exposedMainAgentSystemPrompt = exposedMainAgentSystemPrompt || request.messages.contains { $0.content.contains("MAIN_AGENT_SYSTEM_PROMPT_SENTINEL") }
        switch requestCount {
        case 1:
            return AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "wrong-search", name: "cloud_kb_recent_context", argumentsJSON: #"{"query":"Connor","limit":20}"#)], finishReason: .toolCalls)
        case 2:
            return AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "wrong-write", name: "cloud_kb_l3_update_knowledge", argumentsJSON: #"{"search_context_id":"search-1","decision":"create_new","semantic_terms":["Connor"],"payload":{"kind":"reusable_knowledge","stable_key":"connor-publishing","valid_from":"2026-07-16T00:00:00Z","payload":{"title":"Connor 发布流程"}}}"#)], finishReason: .toolCalls)
        default:
            return AgentModelResponse(text: CloudKnowledgeExtractionPrompt.completionMarker)
        }
    }
}

private actor CloudKnowledgeWriteAssistProvider {
    var requestCount = 0

    func complete(_ request: AgentModelRequest) throws -> AgentModelResponse {
        requestCount += 1
        if requestCount == 1 {
            return AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "read", name: "cloud_kb_read_record", argumentsJSON: #"{"query":"Answer cache","limit":20}"#)], finishReason: .toolCalls)
        }
        if requestCount == 2 {
            return AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "write", name: "cloud_kb_l3_update_knowledge", argumentsJSON: #"{"search_context_id":"search-1","decision":"create_new","semantic_terms":["answer-package"],"payload":{"kind":"reusable_knowledge","stable_key":"answer-cache-refresh","valid_from":"2026-07-16T00:00:00Z","payload":{"title":"Answer cache refresh","text":"Answer cache uses bounded refresh policies."}}}"#)], finishReason: .toolCalls)
        }
        return AgentModelResponse(text: "\(CloudKnowledgeExtractionPrompt.completionMarker)\n已完成知识整理")
    }
}

private actor CloudKnowledgeHTTPTransport: ConnorBackendHTTPTransport {
    var requests: [URLRequest] = []; var failWithConflict = false
    func enableConflict() { failWithConflict = true }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if failWithConflict { return response(request, 409, #"{"code":"publication_conflict","message":"changed","current_sequence":9}"#) }
        return response(request, 200, #"{"data":{"id":"run-1","knowledge_base_id":"kb 1","client_run_id":"client-1","expected_base_sequence":7,"current_staged_sequence":0,"status":"open","schema_version":"v2","created_at":"2026-07-13T10:00:00Z","updated_at":"2026-07-13T10:00:00Z","expires_at":"2026-07-14T10:00:00Z"}}"#)
    }
    private func response(_ request: URLRequest, _ status: Int, _ json: String) -> (Data, URLResponse) { (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!) }
}

private actor InMemoryCloudKnowledgeAPI: CloudKnowledgeAPI {
    var stagedSequence = 0; var operations: [CloudKnowledgeOperation] = []; var searchViews: [CloudKnowledgeSearchView] = []; var searchStagedSequences: [Int] = []
    var receivedPayloadTexts: [String] { operations.compactMap { if case .string(let value) = $0.payload["text"] { value } else { nil } } }
    var receivedRequestBodiesContainRawConversation: Bool { operations.contains { operation in operation.payload.values.contains { if case .string(let value) = $0 { value.contains("raw one") || value.contains("raw two") } else { false } } } }
    func createPublicationRun(knowledgeBaseID: String, request: CloudKnowledgeCreateRunRequest) async throws -> CloudKnowledgePublicationRun { .init(id: "run", knowledgeBaseID: knowledgeBaseID, clientRunID: request.clientRunID, expectedBaseSequence: request.expectedBaseSequence) }
    func publicationRun(id: String) async throws -> CloudKnowledgePublicationRun { .init(id: id, knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: 4, currentStagedSequence: stagedSequence, status: .staging) }
    func appendOperations(runID: String, request: CloudKnowledgeOperationBatchRequest) async throws -> CloudKnowledgeOperationBatchResponse { operations += request.operations; stagedSequence += 1; return .init(acceptedOperationIDs: request.operations.map(\.operationID), stagedSequence: stagedSequence) }
    func validate(runID: String) async throws -> CloudKnowledgeValidationResult { .init(valid: true, issues: [], stagedSequence: stagedSequence) }
    func rebase(runID: String, request: CloudKnowledgeRebaseRequest) async throws -> CloudKnowledgePublicationRun { .init(id: runID, knowledgeBaseID: "kb", clientRunID: "client", expectedBaseSequence: request.expectedBaseSequence, currentStagedSequence: stagedSequence) }
    func commit(runID: String) async throws -> CloudKnowledgeCommitResult { .init(publicationRunID: runID, knowledgeSequence: 5, indexedSequence: 5) }
    func abandon(runID: String) async throws {}
    func search(knowledgeBaseID: String, channel: CloudKnowledgeSearchChannel, request: CloudKnowledgeSearchRequest) async throws -> CloudKnowledgeSearchResponse {
        searchViews.append(request.view); searchStagedSequences.append(stagedSequence)
        let hits = operations.isEmpty ? [] : [CloudKnowledgeSearchHit(identityID: "staged-1", layer: .l3, kind: "reusable_knowledge", text: "Earlier staged knowledge", staged: true)]
        return .init(searchContextID: "search-\(searchViews.count)", channel: channel, baseSequence: 4, stagedSequence: stagedSequence, results: hits)
    }
}
