import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct CloudKnowledgeExtractionSourcePreview: Codable, Sendable, Equatable {
    public var sessionID: String
    public var title: String
    public var turns: [CloudKnowledgeSourceTurn]
    public var turnCount: Int
    public var characterCount: Int

    public init(session: AgentSession) {
        let turns = CloudKnowledgeExtractionPrompt.sourceTurns(session: session)
        self.sessionID = session.id
        self.title = session.title
        self.turns = turns
        self.turnCount = turns.count
        self.characterCount = turns.reduce(0) { $0 + $1.userMessage.count + $1.assistantFinalResponse.count }
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title, turns
        case turnCount = "turn_count"
        case characterCount = "character_count"
    }
}

public struct CloudKnowledgeExtractionPromptPreview: Codable, Sendable, Equatable {
    public var sessionID: String
    public var modelMessages: [AgentModelMessage]
    public var systemPromptCharacterCount: Int
    public var userPromptCharacterCount: Int
    public var totalMessageCharacterCount: Int

    public init(session: AgentSession, processingTime: Date = Date()) {
        let messages = [
            AgentModelMessage(role: .system, content: CloudKnowledgeExtractionPrompt.systemInstruction),
            AgentModelMessage(role: .user, content: CloudKnowledgeExtractionPrompt.sourcePrompt(session: session, processingTime: processingTime))
        ]
        self.sessionID = session.id
        self.modelMessages = messages
        self.systemPromptCharacterCount = messages[0].content.count
        self.userPromptCharacterCount = messages[1].content.count
        self.totalMessageCharacterCount = messages.reduce(0) { $0 + $1.content.count }
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case modelMessages = "model_messages"
        case systemPromptCharacterCount = "system_prompt_character_count"
        case userPromptCharacterCount = "user_prompt_character_count"
        case totalMessageCharacterCount = "total_message_character_count"
    }
}

public struct CloudKnowledgeExtractionCLIRunSummary: Codable, Sendable, Equatable {
    public var status: String
    public var sessionID: String
    public var knowledgeBaseID: String
    public var publicationRunID: String
    public var clientRunID: String
    public var modelID: String
    public var summary: String

    private enum CodingKeys: String, CodingKey {
        case status
        case sessionID = "session_id"
        case knowledgeBaseID = "knowledge_base_id"
        case publicationRunID = "publication_run_id"
        case clientRunID = "client_run_id"
        case modelID = "model_id"
        case summary
    }
}

public enum CloudKnowledgeExtractionTraceRenderer {
    public static func render(_ event: CloudKnowledgeExtractionTraceEvent) -> String {
        var lines = ["", "[knowledge-market trace #\(event.sequence) | iteration \(event.iteration) | \(event.kind.rawValue)]"]
        switch event.kind {
        case .modelRequest:
            lines.append("model=\(event.modelID) message_chars=\(event.messageCharacterCount ?? 0) tool_definition_chars=\(event.toolDefinitionCharacterCount ?? 0) temperature=\(event.temperature ?? 0)")
            for (index, message) in (event.messages ?? []).enumerated() {
                lines.append("--- message \(index + 1) role=\(message.role.rawValue) chars=\(message.content.count) ---")
                lines.append(message.content)
                if let calls = message.toolCalls, !calls.isEmpty {
                    for call in calls {
                        lines.append("tool_call id=\(call.id) name=\(call.name) arguments_chars=\(call.argumentsJSON.count)")
                        lines.append(call.argumentsJSON)
                    }
                }
            }
            for tool in event.tools ?? [] {
                lines.append("--- tool \(tool.name) chars=\(tool.characterCount) ---")
                lines.append("description: \(tool.description)")
                lines.append("input_schema: \(tool.inputSchemaJSON)")
                lines.append("input_examples: \(tool.inputExamplesJSON)")
            }
        case .modelResponse:
            guard let response = event.response else { break }
            lines.append("model=\(event.modelID) finish_reason=\(response.finishReason.rawValue) parsed_chars=\(response.characterCount) text_chars=\(response.textCharacterCount) tool_call_chars=\(response.toolCallCharacterCount) raw_response_chars=\(response.rawResponseCharacterCount)")
            lines.append("text:")
            lines.append(response.text ?? "<nil>")
            for call in response.toolCalls {
                lines.append("tool_call id=\(call.id) name=\(call.name) arguments_chars=\(call.argumentsJSON.count)")
                lines.append(call.argumentsJSON)
            }
            if let usage = response.usage {
                lines.append("usage prompt=\(usage.promptTokens) completion=\(usage.completionTokens) total=\(usage.totalTokens)")
            }
            if let raw = response.rawResponseJSON {
                lines.append("raw_response_json chars=\(raw.count):")
                lines.append(raw)
            }
            if let metadata = response.providerMetadata {
                lines.append("provider_metadata:")
                lines.append(json(metadata))
            }
            if !response.warnings.isEmpty { lines.append("warnings: \(response.warnings.joined(separator: " | "))") }
        case .toolExecution:
            if let call = event.toolCall {
                lines.append("tool_call id=\(call.id) name=\(call.name) arguments_chars=\(call.argumentsJSON.count)")
                lines.append(call.argumentsJSON)
            }
        case .toolResult:
            if let result = event.toolResult {
                let content = result.contentJSON ?? result.contentText
                lines.append("tool_result call_id=\(result.toolCallID) name=\(result.toolName) chars=\(content.count)")
                lines.append(content)
            }
        case .modelError:
            lines.append("model=\(event.modelID)")
            lines.append("error: \(event.error ?? "unknown")")
        case .toolError:
            if let call = event.toolCall { lines.append("tool_call id=\(call.id) name=\(call.name)\n\(call.argumentsJSON)") }
            lines.append("error: \(event.error ?? "unknown")")
        }
        return lines.joined(separator: "\n")
    }

    public static func jsonLine(_ event: CloudKnowledgeExtractionTraceEvent) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(event) else { return #"{"error":"trace_encoding_failed"}"# }
        return String(decoding: data, as: UTF8.self)
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "<encoding failed>" }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum AppCloudKnowledgeCLIRouter {
    public static let usage = "connor knowledge-market source|prompt <session-id> | debug-extract <session-id> --knowledge-base <id> --publication-run <id> [--client-run <id>] [--backend-url <url>] [--format text|jsonl] [--max-iterations N] [--max-tool-calls N] [--max-tool-errors N]"

    public static func route(
        args: [String],
        encoder: JSONEncoder,
        traceOutput: @escaping @Sendable (String) -> Void = { print($0) }
    ) async throws -> String {
        let command = args.first ?? "help"
        if command == "help" || command == "--help" {
            return try encode(["usage": usage], encoder: encoder)
        }
        guard let sessionID = args.dropFirst().first, !sessionID.hasPrefix("--") else {
            return try encode(["error": "missing_session_id", "usage": usage], encoder: encoder)
        }
        let live = try makeLiveContext(sessionID: sessionID)
        switch command {
        case "source":
            return try encode(CloudKnowledgeExtractionSourcePreview(session: live.session), encoder: encoder)
        case "prompt":
            return try encode(CloudKnowledgeExtractionPromptPreview(session: live.session), encoder: encoder)
        case "debug-extract":
            guard let knowledgeBaseID = optionValue("--knowledge-base", in: args) else {
                return try encode(["error": "missing_knowledge_base_id", "usage": usage], encoder: encoder)
            }
            guard let publicationRunID = optionValue("--publication-run", in: args) else {
                return try encode(["error": "missing_publication_run_id", "usage": usage], encoder: encoder)
            }
            let format = optionValue("--format", in: args) ?? "text"
            guard ["text", "jsonl"].contains(format) else {
                return try encode(["error": "unknown_trace_format", "usage": usage], encoder: encoder)
            }
            let clientRunID = optionValue("--client-run", in: args) ?? "cli-\(UUID().uuidString)"
            let backendURLString = optionValue("--backend-url", in: args)
                ?? ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"]
                ?? "http://localhost:8080"
            guard let backendURL = URL(string: backendURLString) else {
                return try encode(["error": "invalid_backend_url", "value": backendURLString], encoder: encoder)
            }
            let provider = live.factory.makeAgentModelProvider(sessionLLMOverride: live.sessionLLMOverride)
            let accountCredentials = AppConnorAccountCredentialStore()
            let authenticatedSession = ConnorBackendAuthenticatedSession(
                api: ConnorBackendAPIClient(baseURL: backendURL),
                credentials: accountCredentials
            )
            let api = CloudKnowledgeAPIClient(
                baseURL: backendURL,
                credentials: StoredCloudKnowledgeCredentialProvider(credentials: accountCredentials),
                refreshRejectedToken: { rejectedToken in
                    try await authenticatedSession.refreshAccessToken(afterRejectedToken: rejectedToken)
                }
            )
            let runner = CloudKnowledgeLLMGenerationRunner(
                maximumIterations: intOption("--max-iterations", in: args, default: 48),
                maximumToolCallsPerIteration: intOption("--max-tool-calls", in: args, default: 4),
                maximumTotalToolErrors: intOption("--max-tool-errors", in: args, default: 8)
            )
            let result = try await runner.generate(
                session: live.session,
                knowledgeBaseID: knowledgeBaseID,
                publicationRunID: publicationRunID,
                clientRunID: clientRunID,
                api: api,
                provider: provider,
                trace: { event in
                    traceOutput(format == "jsonl" ? CloudKnowledgeExtractionTraceRenderer.jsonLine(event) : CloudKnowledgeExtractionTraceRenderer.render(event))
                }
            )
            let summary = CloudKnowledgeExtractionCLIRunSummary(
                status: "completed",
                sessionID: sessionID,
                knowledgeBaseID: knowledgeBaseID,
                publicationRunID: publicationRunID,
                clientRunID: clientRunID,
                modelID: provider.modelID,
                summary: result.summary
            )
            return try format == "jsonl" ? encodeCompact(summary) : encode(summary, encoder: encoder)
        default:
            return try encode(["error": "unknown_knowledge_market_command", "usage": usage], encoder: encoder)
        }
    }

    private struct LiveContext {
        var session: AgentSession
        var sessionLLMOverride: SessionLLMOverride?
        var factory: AppGraphAgentRuntimeFactory
    }

    private static func makeLiveContext(sessionID: String) throws -> LiveContext {
        let paths = try AppStoragePaths.live()
        try paths.ensureDirectoryHierarchy()
        let store = try AppGraphBootstrapper(paths: paths).bootstrapStore()
        let repository = AppChatSessionRepository(store: store, storagePaths: paths)
        guard let session = try repository.loadSession(id: sessionID) else {
            throw AppChatSessionRepositoryError.sessionNotFound(sessionID)
        }
        let factory = AppGraphAgentRuntimeFactory(
            store: store,
            settingsRepository: AppLLMSettingsRepository.cliRepository(),
            storagePaths: paths
        )
        return LiveContext(
            session: session,
            sessionLLMOverride: try repository.loadSessionState(sessionID: sessionID)?.llmOverride,
            factory: factory
        )
    }

    private static func optionValue(_ option: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: option), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func intOption(_ option: String, in args: [String], default defaultValue: Int) -> Int {
        guard let raw = optionValue(option, in: args), let value = Int(raw), value > 0 else { return defaultValue }
        return value
    }

    private static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func encodeCompact<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
