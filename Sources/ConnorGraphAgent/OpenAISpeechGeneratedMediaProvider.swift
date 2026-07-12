import Foundation

public protocol AgentByteStreamHTTPClient: Sendable {
    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<Data, Error>
}

public struct URLSessionAgentByteStreamHTTPClient: AgentByteStreamHTTPClient, Sendable {
    public init() {}

    public func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<Data, Error> {
        var urlRequest = request.timeoutInterval.map { URLRequest(url: request.url, timeoutInterval: $0) } ?? URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw OpenAISpeechGeneratedMediaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenAISpeechGeneratedMediaError.providerRejected(statusCode: http.statusCode) }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var chunk = Data()
                    chunk.reserveCapacity(16_384)
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= 16_384 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}

public enum OpenAISpeechGeneratedMediaError: Error, Sendable, Equatable {
    case unsupportedRequestKind
    case unsupportedByCurrentModel(String)
    case invalidResponse
    case providerRejected(statusCode: Int)
    case emptyAudio
}

public struct OpenAISpeechGeneratedMediaProvider<Client: AgentByteStreamHTTPClient>: AgentGeneratedMediaProvider, Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var modelID: String
    public var capabilities: AgentModelCapabilities
    public var client: Client
    public var timeout: TimeInterval

    public init(baseURL: URL, apiKey: String, modelID: String, capabilities: AgentModelCapabilities, client: Client, timeout: TimeInterval = 300) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.capabilities = capabilities
        self.client = client
        self.timeout = timeout
    }

    public func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard request.kind == .speech else { throw OpenAISpeechGeneratedMediaError.unsupportedRequestKind }
                    switch CurrentModelMediaCapabilityGate.decision(modelID: modelID, capabilities: capabilities, requestKind: .speech, requiresStreaming: true) {
                    case .supported: break
                    case .unsupportedByCurrentModel(let reason): throw OpenAISpeechGeneratedMediaError.unsupportedByCurrentModel(reason)
                    }
                    let format = AgentGeneratedAudioFormat(encoding: "pcm_s16le", sampleRate: 24_000, channelCount: 1, bitsPerChannel: 16)
                    continuation.yield(.started)
                    continuation.yield(.audioStreamStarted(format))
                    let stream = try await client.stream(try makeRequest(request))
                    let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent("connor-speech-\(UUID().uuidString).pcm")
                    FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: temporaryURL)
                    var byteCount: Int64 = 0
                    var sequence = 0
                    do {
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            guard !chunk.isEmpty else { continue }
                            try handle.write(contentsOf: chunk)
                            byteCount += Int64(chunk.count)
                            continuation.yield(.audioChunk(sequence: sequence, data: chunk, presentationTime: nil))
                            sequence += 1
                        }
                        try handle.close()
                    } catch {
                        try? handle.close()
                        try? FileManager.default.removeItem(at: temporaryURL)
                        throw error
                    }
                    guard byteCount > 0 else {
                        try? FileManager.default.removeItem(at: temporaryURL)
                        throw OpenAISpeechGeneratedMediaError.emptyAudio
                    }
                    continuation.yield(.completed(AgentGeneratedMediaArtifact(
                        temporaryFileURL: temporaryURL,
                        mimeType: "audio/pcm",
                        byteCount: byteCount,
                        generationMetadata: AgentAttachmentGenerationMetadata(
                            providerID: "openai-speech",
                            modelID: modelID,
                            parameters: request.options.merging(["format": "pcm", "sample_rate": "24000"]) { current, _ in current }
                        )
                    )))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    private func makeRequest(_ request: AgentGeneratedMediaRequest) throws -> AgentHTTPRequest {
        var body: [String: Any] = [
            "model": modelID,
            "input": request.prompt,
            "voice": request.options["voice"] ?? "alloy",
            "response_format": "pcm"
        ]
        if let instructions = request.options["instructions"], !instructions.isEmpty { body["instructions"] = instructions }
        if let speed = request.options["speed"].flatMap(Double.init) { body["speed"] = speed }
        return AgentHTTPRequest(
            url: baseURL.appendingPathComponent("audio/speech"),
            method: "POST",
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            timeoutInterval: timeout
        )
    }
}

public extension OpenAISpeechGeneratedMediaProvider where Client == URLSessionAgentByteStreamHTTPClient {
    init(baseURL: URL, apiKey: String, modelID: String, capabilities: AgentModelCapabilities, timeout: TimeInterval = 300) {
        self.init(baseURL: baseURL, apiKey: apiKey, modelID: modelID, capabilities: capabilities, client: URLSessionAgentByteStreamHTTPClient(), timeout: timeout)
    }
}
