import Foundation

public struct FluxImageGeneratedMediaConfig: Sendable, Equatable {
    public var baseURL: URL; public var apiKey: String; public var model: String; public var pollInterval: TimeInterval; public var maxPollAttempts: Int; public var requestTimeout: TimeInterval
    public init(baseURL: URL = URL(string: "https://api.bfl.ai/v1")!, apiKey: String, model: String = "flux-2-pro", pollInterval: TimeInterval = 1, maxPollAttempts: Int = 300, requestTimeout: TimeInterval = 300) { self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.pollInterval = pollInterval; self.maxPollAttempts = maxPollAttempts; self.requestTimeout = requestTimeout }
}
public enum FluxImageGeneratedMediaError: Error, Sendable, Equatable { case unsupportedRequestKind, providerRejected(Int), missingTaskID, failed(String), timedOut, missingImageURL, invalidImageData }

public struct FluxImageGeneratedMediaProvider<Client: AgentHTTPClient>: AgentGeneratedMediaProvider, Sendable {
    public var config: FluxImageGeneratedMediaConfig; public var httpClient: Client
    public var modelID: String { config.model }
    public var capabilities: AgentModelCapabilities { AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false, generatedMediaCapabilities: [.imageGeneration]) }
    public init(config: FluxImageGeneratedMediaConfig, httpClient: Client) { self.config = config; self.httpClient = httpClient }
    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> { AsyncThrowingStream { continuation in Task {
        do {
            guard request.kind == .image else { throw FluxImageGeneratedMediaError.unsupportedRequestKind }; try Task.checkCancellation(); continuation.yield(.started)
            var body: [String: Any] = ["prompt": request.prompt]
            if let width = request.options["width"].flatMap(Int.init) { body["width"] = width }; if let height = request.options["height"].flatMap(Int.init) { body["height"] = height }
            var client = httpClient
            let submission = try await client.send(AgentHTTPRequest(url: config.baseURL.appendingPathComponent(modelID), method: "POST", headers: ["x-key": config.apiKey, "Content-Type": "application/json"], body: try JSONSerialization.data(withJSONObject: body), timeoutInterval: config.requestTimeout))
            guard (200..<300).contains(submission.statusCode) else { throw FluxImageGeneratedMediaError.providerRejected(submission.statusCode) }
            let submitted = try Self.dictionary(submission.body); guard let id = (submitted["id"] ?? submitted["request_id"]) as? String else { throw FluxImageGeneratedMediaError.missingTaskID }
            for attempt in 0..<config.maxPollAttempts {
                try Task.checkCancellation(); if config.pollInterval > 0 { try await Task.sleep(for: .seconds(config.pollInterval)) }
                let url = config.baseURL.appendingPathComponent("get_result").appending(queryItems: [URLQueryItem(name: "id", value: id)])
                let response = try await client.send(AgentHTTPRequest(url: url, method: "GET", headers: ["x-key": config.apiKey], body: Data(), timeoutInterval: config.requestTimeout))
                guard (200..<300).contains(response.statusCode) else { throw FluxImageGeneratedMediaError.providerRejected(response.statusCode) }
                let result = try Self.dictionary(response.body); let status = (result["status"] as? String)?.lowercased() ?? ""
                if ["failed", "error"].contains(status) { throw FluxImageGeneratedMediaError.failed((result["error"] as? String) ?? status) }
                if ["ready", "completed", "succeeded"].contains(status) {
                    let sample = result["sample"] as? String ?? (result["result"] as? [String: Any])?["sample"] as? String
                    guard let raw = sample, let imageURL = URL(string: raw) else { throw FluxImageGeneratedMediaError.missingImageURL }
                    let image = try await client.send(AgentHTTPRequest(url: imageURL, method: "GET", headers: [:], body: Data(), timeoutInterval: config.requestTimeout)); guard (200..<300).contains(image.statusCode), !image.body.isEmpty else { throw FluxImageGeneratedMediaError.invalidImageData }
                    let mime = imageURL.pathExtension.lowercased() == "jpg" || imageURL.pathExtension.lowercased() == "jpeg" ? "image/jpeg" : "image/png"; let ext = mime == "image/jpeg" ? "jpg" : "png"
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("connor-flux-\(UUID().uuidString).\(ext)"); try image.body.write(to: file, options: .atomic)
                    continuation.yield(.completed(AgentGeneratedMediaArtifact(temporaryFileURL: file, mimeType: mime, byteCount: Int64(image.body.count), generationMetadata: AgentAttachmentGenerationMetadata(providerID: "black-forest-labs", modelID: modelID, responseID: id, parameters: request.options)))); continuation.finish(); return
                }
                continuation.yield(.progress(Double(attempt + 1) / Double(config.maxPollAttempts)))
            }
            throw FluxImageGeneratedMediaError.timedOut
        } catch { continuation.finish(throwing: error) }
    }} }
    private static func dictionary(_ data: Data) throws -> [String: Any] { (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
}
