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
        AgentModelResponse(text: "PRIVATE_RESPONSE_BODY", usage: AgentModelUsage(promptTokens: 12, completionTokens: 3), finishReason: .stop)
    }
    let provider = AuditedAgentModelProvider(provider: base, recorder: store)
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
    #expect(record.inputCharacterCount == 19)
    #expect(record.outputCharacterCount == 21)
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
        auditContext: .init(requestKind: .conversationTurn, operation: "AgentLoop.stream", initiator: .foreground)
    )) {}

    let records = store.records()
    #expect(records.count == 1)
    #expect(records.first?.executionMode == .streaming)
    #expect(records.first?.totalTokens == 6)
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
