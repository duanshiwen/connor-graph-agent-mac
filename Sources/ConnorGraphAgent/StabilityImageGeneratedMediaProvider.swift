import Foundation

public struct StabilityImageGeneratedMediaConfig: Sendable, Equatable {
    public var baseURL: URL; public var apiKey: String; public var model: String; public var requestTimeout: TimeInterval
    public init(baseURL: URL = URL(string: "https://api.stability.ai/v2beta")!, apiKey: String, model: String = "stable-image-ultra", requestTimeout: TimeInterval = 300) { self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.requestTimeout = requestTimeout }
}
public enum StabilityImageGeneratedMediaError: Error, Sendable, Equatable { case unsupportedRequestKind, unsupportedModel(String), providerRejected(Int), missingImage, invalidBase64 }
public struct StabilityImageGeneratedMediaProvider<Client: AgentHTTPClient>: AgentGeneratedMediaProvider, Sendable {
    public var config: StabilityImageGeneratedMediaConfig; public var httpClient: Client; public var modelID: String { config.model }
    public static var supportedModels: Set<String> { ["stable-image-ultra", "stable-image-core", "sd3.5-large", "sd3.5-large-turbo", "sd3.5-medium", "sd3.5-flash"] }
    public var capabilities: AgentModelCapabilities { AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false, generatedMediaCapabilities: Self.supportedModels.contains(modelID) ? [.imageGeneration] : []) }
    public init(config: StabilityImageGeneratedMediaConfig, httpClient: Client) { self.config = config; self.httpClient = httpClient }
    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> { AsyncThrowingStream { continuation in Task {
        do {
            guard request.kind == .image else { throw StabilityImageGeneratedMediaError.unsupportedRequestKind }; guard Self.supportedModels.contains(modelID) else { throw StabilityImageGeneratedMediaError.unsupportedModel(modelID) }; continuation.yield(.started)
            var fields = ["prompt": request.prompt, "output_format": request.options["output_format"] ?? "png"]
            if let ratio = request.options["aspect_ratio"] { fields["aspect_ratio"] = ratio }; if let negative = request.options["negative_prompt"] { fields["negative_prompt"] = negative }
            let isSD3 = modelID.hasPrefix("sd3.5"); if isSD3 { fields["model"] = modelID; fields["mode"] = "text-to-image" }
            let boundary = "ConnorBoundary\(UUID().uuidString)"; let body = Self.multipart(fields: fields, boundary: boundary)
            let path = isSD3 ? "stable-image/generate/sd3" : modelID == "stable-image-core" ? "stable-image/generate/core" : "stable-image/generate/ultra"
            var client = httpClient; let response = try await client.send(AgentHTTPRequest(url: config.baseURL.appendingPathComponent(path), method: "POST", headers: ["Authorization": "Bearer \(config.apiKey)", "Accept": "application/json", "Content-Type": "multipart/form-data; boundary=\(boundary)"], body: body, timeoutInterval: config.requestTimeout))
            guard (200..<300).contains(response.statusCode) else { throw StabilityImageGeneratedMediaError.providerRejected(response.statusCode) }
            let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]; guard let encoded = (object?["image"] ?? object?["base64"]) as? String else { throw StabilityImageGeneratedMediaError.missingImage }; guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !data.isEmpty else { throw StabilityImageGeneratedMediaError.invalidBase64 }
            let format = fields["output_format"] ?? "png"; let mime = format == "jpeg" || format == "jpg" ? "image/jpeg" : format == "webp" ? "image/webp" : "image/png"; let ext = mime == "image/jpeg" ? "jpg" : format
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("connor-stability-\(UUID().uuidString).\(ext)"); try data.write(to: file, options: .atomic)
            continuation.yield(.completed(AgentGeneratedMediaArtifact(temporaryFileURL: file, mimeType: mime, byteCount: Int64(data.count), generationMetadata: AgentAttachmentGenerationMetadata(providerID: "stability-ai", modelID: modelID, responseID: object?["id"] as? String, parameters: request.options)))); continuation.finish()
        } catch { continuation.finish(throwing: error) }
    }} }
    private static func multipart(fields: [String: String], boundary: String) -> Data { var value = ""; for key in fields.keys.sorted() { value += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n" }; value += "--\(boundary)--\r\n"; return Data(value.utf8) }
}
