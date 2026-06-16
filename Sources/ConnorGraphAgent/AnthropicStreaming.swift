import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AnthropicThinkingDisplay: String, Codable, Sendable, Equatable {
    case summarized
    case omitted
}

public enum AnthropicThinkingConfig: Codable, Sendable, Equatable {
    case enabled(budgetTokens: Int, display: AnthropicThinkingDisplay? = nil)
    case adaptive(display: AnthropicThinkingDisplay? = nil)

    public var jsonObject: [String: Any] {
        switch self {
        case .enabled(let budgetTokens, let display):
            var object: [String: Any] = ["type": "enabled", "budget_tokens": budgetTokens]
            if let display { object["display"] = display.rawValue }
            return object
        case .adaptive(let display):
            var object: [String: Any] = ["type": "adaptive"]
            if let display { object["display"] = display.rawValue }
            return object
        }
    }
}

public enum AnthropicPromptCacheTTL: String, Codable, Sendable, Equatable {
    case fiveMinutes = "5m"
    case oneHour = "1h"
}

public struct AnthropicPromptCacheConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var ttl: AnthropicPromptCacheTTL?

    public init(enabled: Bool = false, ttl: AnthropicPromptCacheTTL? = nil) {
        self.enabled = enabled
        self.ttl = ttl
    }

    public var jsonObject: [String: Any]? {
        guard enabled else { return nil }
        var object: [String: Any] = ["type": "ephemeral"]
        if let ttl { object["ttl"] = ttl.rawValue }
        return object
    }
}

public enum AnthropicServerTool: Codable, Sendable, Equatable {
    case webSearch(version: String = "web_search_20250305", maxUses: Int? = nil, allowedDomains: [String] = [], blockedDomains: [String] = [])
    case webFetch(version: String = "web_fetch_20250910", allowedDomains: [String] = [], blockedDomains: [String] = [])

    public var jsonObject: [String: Any] {
        switch self {
        case .webSearch(let version, let maxUses, let allowedDomains, let blockedDomains):
            var object: [String: Any] = ["type": version, "name": "web_search"]
            if let maxUses { object["max_uses"] = maxUses }
            if !allowedDomains.isEmpty { object["allowed_domains"] = allowedDomains }
            if !blockedDomains.isEmpty { object["blocked_domains"] = blockedDomains }
            return object
        case .webFetch(let version, let allowedDomains, let blockedDomains):
            var object: [String: Any] = ["type": version, "name": "web_fetch"]
            if !allowedDomains.isEmpty { object["allowed_domains"] = allowedDomains }
            if !blockedDomains.isEmpty { object["blocked_domains"] = blockedDomains }
            return object
        }
    }
}

public struct AnthropicCompatibleFeatureOptions: Codable, Sendable, Equatable {
    public var streamingEnabled: Bool
    public var thinking: AnthropicThinkingConfig?
    public var promptCache: AnthropicPromptCacheConfig
    public var eagerInputStreamingToolNames: Set<String>
    public var cachedToolNames: Set<String>
    public var serverTools: [AnthropicServerTool]
    public var betaHeaders: [String]

    public init(
        streamingEnabled: Bool = true,
        thinking: AnthropicThinkingConfig? = nil,
        promptCache: AnthropicPromptCacheConfig = AnthropicPromptCacheConfig(),
        eagerInputStreamingToolNames: Set<String> = [],
        cachedToolNames: Set<String> = [],
        serverTools: [AnthropicServerTool] = [],
        betaHeaders: [String] = []
    ) {
        self.streamingEnabled = streamingEnabled
        self.thinking = thinking
        self.promptCache = promptCache
        self.eagerInputStreamingToolNames = eagerInputStreamingToolNames
        self.cachedToolNames = cachedToolNames
        self.serverTools = serverTools
        self.betaHeaders = betaHeaders
    }
}

public enum AnthropicStreamingEvent: Sendable, Equatable {
    case messageStart(rawJSON: String)
    case contentBlockStart(index: Int, type: String, rawJSON: String)
    case textDelta(index: Int, text: String)
    case thinkingDelta(index: Int, text: String)
    case signatureDelta(index: Int, signature: String)
    case inputJSONDelta(index: Int, partialJSON: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: AgentModelUsage?)
    case messageStop
    case ping
    case error(String)
    case unknown(event: String?, rawJSON: String)
}

public struct AnthropicSSEParser: Sendable, Equatable {
    public init() {}

    public func parse(_ text: String) -> [AnthropicStreamingEvent] {
        text.components(separatedBy: "\n\n").compactMap(parseFrame)
    }

    public func parseFrame(_ frame: String) -> AnthropicStreamingEvent? {
        var eventName: String?
        var dataLines: [String] = []
        for rawLine in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
        }
        guard !dataLines.isEmpty else { return nil }
        let data = dataLines.joined(separator: "\n")
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return .unknown(event: eventName, rawJSON: data)
        }
        let type = object["type"] as? String ?? eventName
        switch type {
        case "message_start":
            return .messageStart(rawJSON: data)
        case "content_block_start":
            let index = object["index"] as? Int ?? 0
            let contentBlock = object["content_block"] as? [String: Any]
            return .contentBlockStart(index: index, type: contentBlock?["type"] as? String ?? "unknown", rawJSON: data)
        case "content_block_delta":
            let index = object["index"] as? Int ?? 0
            let delta = object["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta": return .textDelta(index: index, text: delta["text"] as? String ?? "")
            case "thinking_delta": return .thinkingDelta(index: index, text: delta["thinking"] as? String ?? "")
            case "signature_delta": return .signatureDelta(index: index, signature: delta["signature"] as? String ?? "")
            case "input_json_delta": return .inputJSONDelta(index: index, partialJSON: delta["partial_json"] as? String ?? "")
            default: return .unknown(event: eventName, rawJSON: data)
            }
        case "content_block_stop":
            return .contentBlockStop(index: object["index"] as? Int ?? 0)
        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            let usageObject = object["usage"] as? [String: Any]
            return .messageDelta(stopReason: delta?["stop_reason"] as? String, usage: AnthropicStreamAccumulator.usage(from: usageObject))
        case "message_stop":
            return .messageStop
        case "ping":
            return .ping
        case "error":
            let error = object["error"] as? [String: Any]
            return .error(error?["message"] as? String ?? data)
        default:
            return .unknown(event: eventName, rawJSON: data)
        }
    }
}

public struct AnthropicStreamAccumulator: Sendable, Equatable {
    private struct Block: Equatable, Sendable {
        var type: String
        var rawStartJSON: String?
        var text: String = ""
        var thinking: String = ""
        var signature: String?
        var inputJSON: String = ""
    }

    private var blocks: [Int: Block] = [:]
    private var textParts: [String] = []
    private var toolCalls: [AgentToolCall] = []
    private var rawContentJSON: [String] = []
    private var stopReason: String?
    private var usage: AgentModelUsage?

    public init() {}

    public mutating func append(_ event: AnthropicStreamingEvent) -> AgentModelStreamEvent? {
        switch event {
        case .contentBlockStart(let index, let type, let rawJSON):
            blocks[index] = Block(type: type, rawStartJSON: rawJSON)
            rawContentJSON.append(rawJSON)
            return nil
        case .textDelta(let index, let text):
            blocks[index, default: Block(type: "text")].text += text
            textParts.append(text)
            return .textDelta(text)
        case .thinkingDelta(let index, let text):
            blocks[index, default: Block(type: "thinking")].thinking += text
            return .thinkingDelta(text)
        case .signatureDelta(let index, let signature):
            blocks[index, default: Block(type: "thinking")].signature = signature
            return nil
        case .inputJSONDelta(let index, let partialJSON):
            blocks[index, default: Block(type: "tool_use")].inputJSON += partialJSON
            let block = blocks[index]
            return .toolInputDelta(toolCallID: nil, name: block?.type == "tool_use" ? toolName(fromRawStart: block?.rawStartJSON) : nil, partialJSON: partialJSON)
        case .contentBlockStop(let index):
            closeBlock(index)
            return nil
        case .messageDelta(let stopReason, let usage):
            if let stopReason { self.stopReason = stopReason }
            if let usage { self.usage = usage }
            return nil
        case .messageStart(let rawJSON):
            return .rawProviderEvent(rawJSON)
        case .messageStop:
            return .completed(response())
        case .ping:
            return nil
        case .error(let message):
            return .rawProviderEvent(message)
        case .unknown(_, let rawJSON):
            rawContentJSON.append(rawJSON)
            return .rawProviderEvent(rawJSON)
        }
    }

    public func response() -> AgentModelResponse {
        let metadata = AgentModelProviderMetadata(
            providerID: "anthropic-compatible",
            rawAssistantContentJSON: rawContentJSON.isEmpty ? nil : "[" + rawContentJSON.joined(separator: ",") + "]",
            stopReason: stopReason
        )
        let finishReason: AgentModelFinishReason = stopReason == "tool_use" ? .toolCalls : (stopReason == "max_tokens" ? .length : .stop)
        return AgentModelResponse(
            text: textParts.isEmpty ? nil : textParts.joined(separator: ""),
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            providerMetadata: metadata
        )
    }

    private mutating func closeBlock(_ index: Int) {
        guard let block = blocks[index] else { return }
        switch block.type {
        case "text":
            rawContentJSON.append(jsonString(["type": "text", "text": block.text]))
        case "thinking":
            var object: [String: Any] = ["type": "thinking", "thinking": block.thinking]
            if let signature = block.signature { object["signature"] = signature }
            rawContentJSON.append(jsonString(object))
        case "tool_use":
            let raw = block.rawStartJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let contentBlock = raw?["content_block"] as? [String: Any]
            let id = contentBlock?["id"] as? String ?? "toolu_\(index)"
            let name = contentBlock?["name"] as? String ?? "unknown_tool"
            let argumentsJSON: String
            if let data = block.inputJSON.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
                argumentsJSON = block.inputJSON
            } else {
                argumentsJSON = jsonString(["INVALID_JSON": block.inputJSON])
            }
            toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argumentsJSON))
            rawContentJSON.append(jsonString(["type": "tool_use", "id": id, "name": name, "input": (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) ?? [:]]))
        default:
            if let rawStartJSON = block.rawStartJSON { rawContentJSON.append(rawStartJSON) }
        }
        blocks.removeValue(forKey: index)
    }

    private func toolName(fromRawStart raw: String?) -> String? {
        guard let raw, let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let block = object["content_block"] as? [String: Any] else { return nil }
        return block["name"] as? String
    }

    private func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func usage(from object: [String: Any]?) -> AgentModelUsage? {
        guard let object else { return nil }
        let input = object["input_tokens"] as? Int ?? 0
        let output = object["output_tokens"] as? Int ?? 0
        return AgentModelUsage(
            promptTokens: input,
            completionTokens: output,
            cacheCreationInputTokens: object["cache_creation_input_tokens"] as? Int,
            cacheReadInputTokens: object["cache_read_input_tokens"] as? Int
        )
    }
}

public protocol AgentSSEHTTPClient: Sendable {
    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error>
}

public struct URLSessionAgentSSEHTTPClient: AgentSSEHTTPClient, Sendable, Equatable {
    public init() {}

    public func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw AnthropicCompatibleProviderError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else { throw AnthropicCompatibleProviderError.httpStatus(httpResponse.statusCode) }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var frame = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !frame.isEmpty {
                                continuation.yield(frame)
                                frame = ""
                            }
                        } else {
                            frame += line + "\n"
                        }
                    }
                    if !frame.isEmpty { continuation.yield(frame) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
