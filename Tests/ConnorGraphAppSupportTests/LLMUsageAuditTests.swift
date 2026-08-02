import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private enum AuditTestError: Error { case failed }

private func auditTestStore() -> (FileLLMUsageAuditStore, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-llm-audit-\(UUID().uuidString)", isDirectory: true)
    return (FileLLMUsageAuditStore(fileURL: root.appendingPathComponent("llm-usage.jsonl")), root)
}

@Test func auditedProviderRecordsUsageAndShapeWithoutPromptOrResponseBodies() async throws {
    let (store, root) = auditTestStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let base = AnyAgentModelProvider(modelID: "audit-model") { _ in
        AgentModelResponse(text: "PRIVATE_RESPONSE_BODY", usage: AgentModelUsage(promptTokens: 12, completionTokens: 3, cacheCreationInputTokens: 2, cacheReadInputTokens: 5), finishReason: .stop)
    }
    let provider = AuditedAgentModelProvider(
        provider: base,
        recorder: store,
        attribution: LLMUsageAuditAttribution(providerMode: "anthropic_messages")
    )
    let request = AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "PRIVATE_PROMPT_BODY")],
        auditContext: AgentLLMRequestAuditContext(
            requestKind: .memoryL1Extraction,
            backgroundJobID: "job-1",
            operation: "MemoryWorker.extract",
            initiator: .background
        )
    )

    _ = try await provider.complete(request)

    let record = try #require(store.records().only)
    #expect(record.requestKind == .memoryL1Extraction)
    #expect(record.operation == "MemoryWorker.extract")
    #expect(record.totalTokens == 15)
    #expect(record.cacheCreationInputTokens == 2)
    #expect(record.cacheReadInputTokens == 5)
    #expect(record.cacheReadRatio == 5.0 / 12.0)
    #expect(record.uncachedInputTokens == 7)
    #expect(record.inputCharacterCount == 19)
    #expect(record.outputCharacterCount == 21)
    let providerSummary = try #require(LLMUsageAuditQueryService(store: store).summary().byProvider.only)
    #expect(providerSummary.key == "anthropic_messages")
    #expect(providerSummary.cacheCreationInputTokens == 2)
    #expect(providerSummary.cacheReadInputTokens == 5)
    #expect(providerSummary.cacheReadRatio == 5.0 / 12.0)
    let persisted = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(!persisted.contains("PRIVATE_PROMPT_BODY"))
    #expect(!persisted.contains("PRIVATE_RESPONSE_BODY"))
}

@Test func auditedProviderRecordsFailuresAndUnclassifiedRequests() async {
    let (store, root) = auditTestStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let base = AnyAgentModelProvider(modelID: "failing-model") { _ in throw AuditTestError.failed }
    let provider = AuditedAgentModelProvider(provider: base, recorder: store)

    await #expect(throws: AuditTestError.self) {
        _ = try await provider.complete(AgentModelRequest(messages: [.init(role: .user, content: "request")]))
    }

    let record = store.records().first
    #expect(record?.status == .failed)
    #expect(record?.requestKind == .unclassified)
    #expect(record?.errorType?.contains("AuditTestError") == true)
}

@Test func auditStoreDecodesLegacyRecordsWithoutUncachedInputTokens() throws {
    let (store, root) = auditTestStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyJSON = #"{"backgroundJobID":null,"cacheCreationInputTokens":null,"cacheReadInputTokens":null,"cancelled":false,"completedAt":"2026-07-30T00:00:00Z","completionTokens":3,"connectionID":null,"containsImages":false,"correlationID":null,"durationMilliseconds":1,"errorMessage":null,"errorType":null,"estimatedInputTokens":12,"executionMode":"completion","finishReason":"stop","generatedByteCount":null,"id":"legacy","initiator":"system","inputCharacterCount":48,"iteration":null,"messageCount":1,"metadata":{},"modelID":"legacy-model","operation":null,"outputCharacterCount":2,"promptTokens":12,"providerID":null,"providerMode":null,"relatedToolNames":[],"requestKind":"unclassified","runID":null,"sessionID":null,"startedAt":"2026-07-30T00:00:00Z","status":"succeeded","toolCallCount":0,"toolDefinitionCount":0,"totalTokens":15}"#
    try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((legacyJSON + "\n").utf8).write(to: store.fileURL)

    let record = try #require(store.records().only)
    #expect(record.id == "legacy")
    #expect(record.uncachedInputTokens == nil)
}

@Test func auditedProviderRecordsStreamingCompletionOnce() async throws {
    let (store, root) = auditTestStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let base = AnyAgentModelProvider(
        modelID: "stream-model",
        complete: { _ in AgentModelResponse(text: "fallback") },
        streamComplete: { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("hello"))
                continuation.yield(.completed(AgentModelResponse(text: "hello", usage: AgentModelUsage(promptTokens: 5, completionTokens: 1))))
                continuation.finish()
            }
        }
    )
    let provider = AuditedAgentModelProvider(provider: base, recorder: store)

    for try await _ in provider.streamComplete(AgentModelRequest(
        messages: [.init(role: .user, content: "stream")],
        auditContext: .init(
            requestKind: .conversationTurn,
            sessionID: "session-1",
            runID: "run-1",
            iteration: 2,
            operation: "AgentLoopController.completeModelRequest",
            initiator: .foreground
        )
    )) {}

    let records = store.records()
    #expect(records.count == 1)
    #expect(records.first?.executionMode == .streaming)
    #expect(records.first?.totalTokens == 6)
    #expect(records.first?.requestKind == .conversationTurn)
    #expect(records.first?.sessionID == "session-1")
    #expect(records.first?.runID == "run-1")
    #expect(records.first?.iteration == 2)
    #expect(records.first?.firstTokenLatencyMilliseconds != nil)
    #expect(store.persistenceHealth().successfulWrites == 1)
    #expect(store.persistenceHealth().isHealthy)
}

@Test func auditStoreReportsPersistenceFailuresInsteadOfSilentlyHidingThem() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-llm-audit-blocked-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("not a directory".utf8).write(to: root)
    let store = FileLLMUsageAuditStore(fileURL: root.appendingPathComponent("llm-usage.jsonl"))
    let base = AnyAgentModelProvider(modelID: "audit-model") { _ in
        AgentModelResponse(text: "ok", usage: AgentModelUsage(promptTokens: 2, completionTokens: 1))
    }
    let provider = AuditedAgentModelProvider(provider: base, recorder: store)

    _ = try await provider.complete(AgentModelRequest(
        messages: [.init(role: .user, content: "hello")],
        auditContext: .init(requestKind: .conversationTurn, sessionID: "session", runID: "run")
    ))

    let health = store.persistenceHealth()
    #expect(health.successfulWrites == 0)
    #expect(health.failedWrites == 1)
    #expect(health.lastError != nil)
    #expect(!health.isHealthy)
}

@Test func auditSummarySeparatesMeteredTokensFromEstimatedCoverage() async throws {
    let (store, root) = auditTestStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let metered = AnyAgentModelProvider(modelID: "metered") { _ in
        AgentModelResponse(text: "ok", usage: AgentModelUsage(promptTokens: 8, completionTokens: 2))
    }
    let unmetered = AnyAgentModelProvider(modelID: "unmetered") { _ in
        AgentModelResponse(text: "ok")
    }
    _ = try await AuditedAgentModelProvider(provider: metered, recorder: store).complete(
        AgentModelRequest(messages: [.init(role: .user, content: "12345678")])
    )
    _ = try await AuditedAgentModelProvider(provider: unmetered, recorder: store).complete(
        AgentModelRequest(messages: [.init(role: .user, content: "12345678")])
    )

    let summary = LLMUsageAuditQueryService(store: store).summary()
    #expect(summary.calls == 2)
    #expect(summary.totalTokens == 10)
    #expect(summary.unmeteredCalls == 1)
    #expect(summary.estimatedInputTokens == 4)
}

@Test func llmAuditCLIShowsTopTokenConsumingOperation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-llm-audit-cli-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let store = FileLLMUsageAuditStore(storagePaths: paths)
    let base = AnyAgentModelProvider(modelID: "ranking-model") { request in
        let tokens = request.auditContext.operation == "LargeBackgroundJob" ? 100 : 10
        return AgentModelResponse(text: "ok", usage: AgentModelUsage(promptTokens: tokens, completionTokens: 1))
    }
    let provider = AuditedAgentModelProvider(provider: base, recorder: store)
    for operation in ["SmallBackgroundJob", "LargeBackgroundJob"] {
        _ = try await provider.complete(AgentModelRequest(
            messages: [.init(role: .user, content: "work")],
            auditContext: .init(requestKind: .memoryBackgroundProcessing, operation: operation, initiator: .background)
        ))
    }
    let encoder = JSONEncoder()

    let output = try LLMUsageAuditCLIRouter.route(args: ["top", "--group-by", "operation"], storagePaths: paths, encoder: encoder)

    #expect(output.contains("LargeBackgroundJob"))
    let large = try #require(output.range(of: "LargeBackgroundJob"))
    let small = try #require(output.range(of: "SmallBackgroundJob"))
    #expect(large.lowerBound < small.lowerBound)
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
