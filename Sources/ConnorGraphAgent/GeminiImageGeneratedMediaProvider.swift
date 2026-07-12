import Foundation

public struct GeminiImageGeneratedMediaConfig: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var requestTimeout: TimeInterval
    public init(baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!, apiKey: String, model: String = "gemini-3.1-flash-image", requestTimeout: TimeInterval = 300) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.requestTimeout = requestTimeout
    }
}

public enum GeminiImageGeneratedMediaError: Error, Sendable, Equatable {
    case unsupportedRequestKind
    case unsupportedModel(String)
    case providerRejected(Int)
    case missingImage
    case invalidBase64
}

public struct GeminiImageGeneratedMediaProvider<Client: AgentHTTPClient>: AgentGeneratedMediaProvider, Sendable {
    public var config: GeminiImageGeneratedMediaConfig
    public var httpClient: Client
    public var modelID: String { config.model }
    public var capabilities: AgentModelCapabilities {
        AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: true, generatedMediaCapabilities: Self.supportedModels.contains(modelID) ? [.imageInput, .imageGeneration] : [.imageInput])
    }
    public static var supportedModels: Set<String> { ["gemini-3.1-flash-image", "gemini-3.1-flash-lite-image", "gemini-3-pro-image", "gemini-2.5-flash-image"] }
    public init(config: GeminiImageGeneratedMediaConfig, httpClient: Client) { self.config = config; self.httpClient = httpClient }

    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        AsyncThrowingStream { continuation in Task {
            do {
                guard request.kind == .image else { throw GeminiImageGeneratedMediaError.unsupportedRequestKind }
                guard Self.supportedModels.contains(modelID) else { throw GeminiImageGeneratedMediaError.unsupportedModel(modelID) }
                continuation.yield(.started)
                let body: [String: Any] = ["model": modelID, "input": request.prompt, "response_format": ["type": "image", "mime_type": request.options["format"] ?? "image/png", "aspect_ratio": request.options["aspect_ratio"] ?? "1:1", "image_size": request.options["image_size"] ?? "1K"]]
                let data = try JSONSerialization.data(withJSONObject: body)
                var client = httpClient
                let response = try await client.send(AgentHTTPRequest(url: config.baseURL.appendingPathComponent("interactions"), method: "POST", headers: ["x-goog-api-key": config.apiKey, "Content-Type": "application/json"], body: data, timeoutInterval: config.requestTimeout))
                guard (200..<300).contains(response.statusCode) else { throw GeminiImageGeneratedMediaError.providerRejected(response.statusCode) }
                let object = try JSONSerialization.jsonObject(with: response.body)
                guard let found = Self.findImage(in: object) else { throw GeminiImageGeneratedMediaError.missingImage }
                guard let bytes = Data(base64Encoded: found.data, options: .ignoreUnknownCharacters), !bytes.isEmpty else { throw GeminiImageGeneratedMediaError.invalidBase64 }
                let mime = found.mimeType ?? "image/png"
                let ext = mime == "image/jpeg" ? "jpg" : mime == "image/webp" ? "webp" : "png"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("connor-gemini-\(UUID().uuidString).\(ext)")
                try bytes.write(to: url, options: .atomic)
                continuation.yield(.completed(AgentGeneratedMediaArtifact(temporaryFileURL: url, mimeType: mime, byteCount: Int64(bytes.count), generationMetadata: AgentAttachmentGenerationMetadata(providerID: "google-gemini-image", modelID: modelID, responseID: Self.stringValue("id", in: object), parameters: request.options))))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }}
    }

    private static func findImage(in value: Any) -> (data: String, mimeType: String?)? {
        if let dictionary = value as? [String: Any] {
            if let data = dictionary["data"] as? String, let type = (dictionary["mime_type"] ?? dictionary["mimeType"]) as? String, type.hasPrefix("image/") { return (data, type) }
            if let image = dictionary["output_image"] as? [String: Any], let data = image["data"] as? String { return (data, (image["mime_type"] ?? image["mimeType"]) as? String) }
            for nested in dictionary.values { if let result = findImage(in: nested) { return result } }
        } else if let array = value as? [Any] { for nested in array { if let result = findImage(in: nested) { return result } } }
        return nil
    }
    private static func stringValue(_ key: String, in value: Any) -> String? { (value as? [String: Any])?[key] as? String }
}
