import Foundation
import Darwin
import ConnorGraphAgent

public struct LLMUsageAuditAttribution: Sendable, Equatable {
    public var providerMode: String?
    public var connectionID: String?

    public init(providerMode: String? = nil, connectionID: String? = nil) {
        self.providerMode = providerMode
        self.connectionID = connectionID
    }
}

public final class FileLLMUsageAuditStore: LLMUsageAuditRecording, @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.connor.llm-usage-audit", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public convenience init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.init(fileURL: storagePaths.auditLogsDirectory.appendingPathComponent("llm-usage.jsonl"), fileManager: fileManager)
    }

    public func record(_ record: LLMUsageAuditRecord) {
        queue.sync {
            do {
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                guard flock(handle.fileDescriptor, LOCK_EX) == 0 else { return }
                defer { flock(handle.fileDescriptor, LOCK_UN) }
                try handle.seekToEnd()
                try handle.write(contentsOf: encoder.encode(record))
                try handle.write(contentsOf: Data("\n".utf8))
            } catch {
                // Auditing is best-effort and must never break an LLM request.
            }
        }
    }

    public func records() -> [LLMUsageAuditRecord] {
        queue.sync {
            guard let data = fileManager.contents(atPath: fileURL.path), !data.isEmpty else { return [] }
            return data.split(separator: UInt8(ascii: "\n")).compactMap { line in
                try? decoder.decode(LLMUsageAuditRecord.self, from: Data(line))
            }
        }
    }
}

public struct LLMUsageAuditFilter: Sendable, Equatable {
    public var requestKind: AgentLLMRequestKind?
    public var model: String?
    public var status: LLMUsageAuditStatus?
    public var since: Date?
    public var limit: Int

    public init(requestKind: AgentLLMRequestKind? = nil, model: String? = nil, status: LLMUsageAuditStatus? = nil, since: Date? = nil, limit: Int = 50) {
        self.requestKind = requestKind
        self.model = model
        self.status = status
        self.since = since
        self.limit = max(1, limit)
    }
}

public struct LLMUsageAuditSummaryRow: Codable, Sendable, Equatable {
    public var key: String
    public var calls: Int
    public var succeeded: Int
    public var failed: Int
    public var cancelled: Int
    public var totalTokens: Int
}

public struct LLMUsageAuditSummary: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var calls: Int
    public var succeeded: Int
    public var failed: Int
    public var cancelled: Int
    public var successRate: Double
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int
    public var unclassifiedCalls: Int
    public var byRequestKind: [LLMUsageAuditSummaryRow]
    public var byModel: [LLMUsageAuditSummaryRow]
    public var byOperation: [LLMUsageAuditSummaryRow]
}

public struct LLMUsageAuditQueryService: Sendable {
    public var store: FileLLMUsageAuditStore

    public init(store: FileLLMUsageAuditStore) { self.store = store }

    public func list(filter: LLMUsageAuditFilter = .init()) -> [LLMUsageAuditRecord] {
        store.records().filter { record in
            if let kind = filter.requestKind, record.requestKind != kind { return false }
            if let model = filter.model, !record.modelID.localizedCaseInsensitiveContains(model) { return false }
            if let status = filter.status, record.status != status { return false }
            if let since = filter.since, record.startedAt < since { return false }
            return true
        }.sorted { $0.startedAt > $1.startedAt }.prefix(filter.limit).map { $0 }
    }

    public func record(id: String) -> LLMUsageAuditRecord? {
        store.records().first { $0.id == id || $0.id.hasPrefix(id) }
    }

    public func summary(since: Date? = nil) -> LLMUsageAuditSummary {
        let records = store.records().filter { since == nil || $0.startedAt >= since! }
        func rows(_ key: (LLMUsageAuditRecord) -> String) -> [LLMUsageAuditSummaryRow] {
            Dictionary(grouping: records, by: key).map { name, values in
                LLMUsageAuditSummaryRow(
                    key: name,
                    calls: values.count,
                    succeeded: values.filter { $0.status == .succeeded }.count,
                    failed: values.filter { $0.status == .failed }.count,
                    cancelled: values.filter { $0.status == .cancelled }.count,
                    totalTokens: values.compactMap(\.totalTokens).reduce(0, +)
                )
            }.sorted { $0.calls == $1.calls ? $0.key < $1.key : $0.calls > $1.calls }
        }
        let succeeded = records.filter { $0.status == .succeeded }.count
        return LLMUsageAuditSummary(
            generatedAt: Date(), calls: records.count, succeeded: succeeded,
            failed: records.filter { $0.status == .failed }.count,
            cancelled: records.filter { $0.status == .cancelled }.count,
            successRate: records.isEmpty ? 0 : Double(succeeded) / Double(records.count),
            promptTokens: records.compactMap(\.promptTokens).reduce(0, +),
            completionTokens: records.compactMap(\.completionTokens).reduce(0, +),
            totalTokens: records.compactMap(\.totalTokens).reduce(0, +),
            cacheCreationInputTokens: records.compactMap(\.cacheCreationInputTokens).reduce(0, +),
            cacheReadInputTokens: records.compactMap(\.cacheReadInputTokens).reduce(0, +),
            unclassifiedCalls: records.filter { $0.requestKind == .unclassified }.count,
            byRequestKind: rows { $0.requestKind.rawValue },
            byModel: rows { $0.modelID },
            byOperation: rows { $0.operation ?? "(unclassified operation)" }.sorted {
                $0.totalTokens == $1.totalTokens ? $0.calls > $1.calls : $0.totalTokens > $1.totalTokens
            }
        )
    }
}

enum LLMUsageAuditProbeRecorder {
    static func record(
        recorder: (any LLMUsageAuditRecording)?,
        kind: AgentLLMRequestKind,
        modelID: String,
        providerMode: String?,
        connectionID: String?,
        operation: String,
        executionMode: LLMUsageAuditExecutionMode = .completion,
        startedAt: Date,
        error: Error? = nil,
        metadata: [String: String] = [:]
    ) {
        guard let recorder else { return }
        let completedAt = Date()
        recorder.record(LLMUsageAuditRecord(
            id: UUID().uuidString, requestKind: kind, startedAt: startedAt, completedAt: completedAt,
            durationMilliseconds: max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000)),
            status: error == nil ? .succeeded : (error is CancellationError ? .cancelled : .failed), executionMode: executionMode,
            modelID: modelID, providerID: nil, providerMode: providerMode, connectionID: connectionID,
            sessionID: nil, runID: nil, backgroundJobID: nil, correlationID: nil, iteration: nil,
            operation: operation, initiator: .system, relatedToolNames: [], promptTokens: nil, completionTokens: nil, totalTokens: nil,
            cacheCreationInputTokens: nil, cacheReadInputTokens: nil, estimatedInputTokens: 0, messageCount: 0, inputCharacterCount: 0,
            toolDefinitionCount: 0, containsImages: executionMode == .generatedMedia, outputCharacterCount: nil, toolCallCount: nil,
            finishReason: nil, generatedByteCount: nil, errorType: error.map { String(reflecting: type(of: $0)) },
            errorMessage: error.map { String($0.localizedDescription.prefix(500)) }, metadata: metadata
        ))
    }
}

public struct AuditedAgentModelProvider: StreamingAgentModelProvider, AgentGeneratedMediaProvider {
    public let modelID: String
    public let capabilities: AgentModelCapabilities
    private let provider: AnyAgentModelProvider
    private let recorder: any LLMUsageAuditRecording
    private let attribution: LLMUsageAuditAttribution

    public init(provider: AnyAgentModelProvider, recorder: any LLMUsageAuditRecording, attribution: LLMUsageAuditAttribution = .init()) {
        self.modelID = provider.modelID
        self.capabilities = provider.capabilities
        self.provider = provider
        self.recorder = recorder
        self.attribution = attribution
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        let startedAt = Date()
        do {
            let response = try await provider.complete(request)
            recorder.record(Self.record(request: request, response: response, modelID: modelID, attribution: attribution, mode: .completion, startedAt: startedAt))
            return response
        } catch {
            recorder.record(Self.record(request: request, error: error, modelID: modelID, attribution: attribution, mode: .completion, startedAt: startedAt))
            throw error
        }
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        let startedAt = Date()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var completedResponse: AgentModelResponse?
                    for try await event in provider.streamComplete(request) {
                        if case .completed(let response) = event { completedResponse = response }
                        continuation.yield(event)
                    }
                    let response = completedResponse ?? AgentModelResponse(text: nil, finishReason: .unknown)
                    recorder.record(Self.record(request: request, response: response, modelID: modelID, attribution: attribution, mode: .streaming, startedAt: startedAt))
                    continuation.finish()
                } catch {
                    recorder.record(Self.record(request: request, error: error, modelID: modelID, attribution: attribution, mode: .streaming, startedAt: startedAt))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        let startedAt = Date()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var byteCount: Int64?
                    for try await event in provider.generateMedia(request) {
                        if case .completed(let artifact) = event { byteCount = artifact.byteCount }
                        continuation.yield(event)
                    }
                    recorder.record(Self.mediaRecord(request: request, byteCount: byteCount, modelID: modelID, attribution: attribution, startedAt: startedAt))
                    continuation.finish()
                } catch {
                    recorder.record(Self.mediaRecord(request: request, error: error, modelID: modelID, attribution: attribution, startedAt: startedAt))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func record(request: AgentModelRequest, response: AgentModelResponse? = nil, error: Error? = nil, modelID: String, attribution: LLMUsageAuditAttribution, mode: LLMUsageAuditExecutionMode, startedAt: Date) -> LLMUsageAuditRecord {
        let completedAt = Date()
        let characters = request.messages.reduce(0) { total, message in
            total + message.content.count + (message.toolCalls?.reduce(0) { $0 + $1.name.count + $1.argumentsJSON.count } ?? 0)
        }
        return LLMUsageAuditRecord(
            id: UUID().uuidString, requestKind: request.auditContext.requestKind, startedAt: startedAt, completedAt: completedAt,
            durationMilliseconds: max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000)), status: status(error), executionMode: mode,
            modelID: modelID, providerID: response?.providerMetadata?.providerID, providerMode: attribution.providerMode, connectionID: attribution.connectionID,
            sessionID: request.auditContext.sessionID, runID: request.auditContext.runID, backgroundJobID: request.auditContext.backgroundJobID,
            correlationID: request.auditContext.correlationID, iteration: request.auditContext.iteration,
            operation: request.auditContext.operation, initiator: request.auditContext.initiator,
            relatedToolNames: Array(Set(request.messages.filter { $0.role == .tool }.compactMap(\.name))).sorted(),
            promptTokens: response?.usage?.promptTokens, completionTokens: response?.usage?.completionTokens, totalTokens: response?.usage?.totalTokens,
            cacheCreationInputTokens: response?.usage?.cacheCreationInputTokens, cacheReadInputTokens: response?.usage?.cacheReadInputTokens,
            estimatedInputTokens: max(1, characters / 4), messageCount: request.messages.count, inputCharacterCount: characters,
            toolDefinitionCount: request.tools.count, containsImages: request.messages.contains { $0.contentParts?.contains { $0.kind == .imageDataURL } == true },
            outputCharacterCount: response?.text?.count, toolCallCount: response?.toolCalls.count, finishReason: response?.finishReason.rawValue,
            generatedByteCount: nil, errorType: error.map { String(reflecting: type(of: $0)) }, errorMessage: sanitized(error?.localizedDescription),
            metadata: request.auditContext.metadata
        )
    }

    private static func mediaRecord(request: AgentGeneratedMediaRequest, byteCount: Int64? = nil, error: Error? = nil, modelID: String, attribution: LLMUsageAuditAttribution, startedAt: Date) -> LLMUsageAuditRecord {
        let completedAt = Date()
        return LLMUsageAuditRecord(
            id: UUID().uuidString, requestKind: request.auditContext.requestKind, startedAt: startedAt, completedAt: completedAt,
            durationMilliseconds: max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000)), status: status(error), executionMode: .generatedMedia,
            modelID: modelID, providerID: nil, providerMode: attribution.providerMode, connectionID: attribution.connectionID,
            sessionID: request.auditContext.sessionID, runID: request.auditContext.runID, backgroundJobID: request.auditContext.backgroundJobID,
            correlationID: request.auditContext.correlationID, iteration: request.auditContext.iteration,
            operation: request.auditContext.operation, initiator: request.auditContext.initiator, relatedToolNames: [],
            promptTokens: nil, completionTokens: nil, totalTokens: nil, cacheCreationInputTokens: nil, cacheReadInputTokens: nil,
            estimatedInputTokens: max(1, request.prompt.count / 4), messageCount: 1, inputCharacterCount: request.prompt.count,
            toolDefinitionCount: 0, containsImages: !request.inputImages.isEmpty, outputCharacterCount: nil, toolCallCount: nil, finishReason: nil,
            generatedByteCount: byteCount, errorType: error.map { String(reflecting: type(of: $0)) }, errorMessage: sanitized(error?.localizedDescription),
            metadata: request.auditContext.metadata
        )
    }

    private static func status(_ error: Error?) -> LLMUsageAuditStatus {
        guard let error else { return .succeeded }
        return error is CancellationError ? .cancelled : .failed
    }

    private static func sanitized(_ message: String?) -> String? {
        guard let message else { return nil }
        return String(message.replacingOccurrences(of: "Bearer ", with: "Bearer [REDACTED] ").prefix(500))
    }
}
