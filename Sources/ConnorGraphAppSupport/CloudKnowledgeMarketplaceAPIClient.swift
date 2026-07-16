import Foundation

public struct CloudKnowledgeMarketplaceAPIClient: CloudKnowledgeMarketplaceAPI, Sendable {
    private let baseURL: URL; private let transport: any ConnorBackendHTTPTransport; private let credentials: any CloudKnowledgeCredentialProvider
    private let encoder: JSONEncoder; private let decoder: JSONDecoder
    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider()) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601; self.decoder = decoder
    }
    public func home() async throws -> CloudMarketplaceHome { try await send("marketplace/home") }
    public func categories() async throws -> [CloudMarketplaceCategory] { try await send("marketplace/categories") }
    public func library() async throws -> CloudMarketplaceLibrary { try await send("marketplace/library") }
    public func search(_ request: CloudMarketplaceSearchRequest) async throws -> [CloudMarketplaceKnowledgeBase] { try await send("marketplace/search", method: "POST", body: request) }
    public func detail(id: String) async throws -> CloudMarketplaceKnowledgeBase { try await send("marketplace/knowledge-bases/\(id)") }
    public func subscribe(id: String) async throws { let _: Empty = try await send("knowledge-bases/\(id)/subscribe", method: "POST", body: Empty()) }
    public func unsubscribe(id: String) async throws { let _: Empty = try await send("knowledge-bases/\(id)/subscribe", method: "DELETE") }
	public func answer(_ request: CloudKnowledgeAnswerRequest) async throws -> CloudKnowledgeAnswerResponse { try await send("knowledge/search/answer", method: "POST", body: request) }
	public func context(_ request: CloudKnowledgeAnswerRequest, channel: CloudKnowledgeSearchChannel) async throws -> CloudKnowledgeAnswerResponse {
		let path = channel == .recentContext ? "knowledge/search/recent-context" : "knowledge/search/knowledge-context"
		return try await send(path, method: "POST", body: request)
	}
    private struct Empty: Codable {}
    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private func send<T: Decodable>(_ path: String, method: String = "GET") async throws -> T { try await send(path, method: method, bodyData: nil) }
    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T { try await send(path, method: method, bodyData: try encoder.encode(body)) }
    private func send<T: Decodable>(_ path: String, method: String, bodyData: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v2/", isDirectory: true))?.absoluteURL else { throw CloudKnowledgeError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = bodyData; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request); guard let http = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }; if http.statusCode == 401 { throw CloudKnowledgeError.unauthorized }; guard (200..<300).contains(http.statusCode) else { throw CloudKnowledgeError.server(status: http.statusCode, code: nil, message: "请求失败（\(http.statusCode)）") }
        if T.self == Empty.self, data.isEmpty { return Empty() as! T }
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) { return envelope.data }
        if let result = try? decoder.decode(T.self, from: data) { return result }
        if T.self == Empty.self { return Empty() as! T }
        throw CloudKnowledgeError.invalidResponse
    }
}
