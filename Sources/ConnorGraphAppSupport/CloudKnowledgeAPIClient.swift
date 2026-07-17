import Foundation

private struct CloudKnowledgeCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public protocol CloudKnowledgeCredentialProvider: Sendable { func accessToken() async throws -> String }

public struct StoredCloudKnowledgeCredentialProvider: CloudKnowledgeCredentialProvider {
    private let credentials: AppConnorAccountCredentialStore
    public init(credentials: AppConnorAccountCredentialStore = .init()) { self.credentials = credentials }
    public func accessToken() async throws -> String {
        guard let token = try credentials.tokens()?.accessToken, !token.isEmpty else { throw CloudKnowledgeError.unauthorized }
        return token
    }
}

public struct RefreshingCloudKnowledgeCredentialProvider: CloudKnowledgeCredentialProvider {
    private let session: ConnorBackendAuthenticatedSession
    public init(session: ConnorBackendAuthenticatedSession) { self.session = session }
    public func accessToken() async throws -> String {
        do { return try await session.accessToken() }
        catch where AppBackendConnectionFailure.isUnreachable(error) { throw error }
        catch { throw CloudKnowledgeError.unauthorized }
    }
    public func refreshedAccessToken(afterRejectedToken token: String) async throws -> String {
        do { return try await session.refreshAccessToken(afterRejectedToken: token) }
        catch where AppBackendConnectionFailure.isUnreachable(error) { throw error }
        catch { throw CloudKnowledgeError.unauthorized }
    }
}

public protocol CloudKnowledgeAPI: Sendable {
    func createPublicationRun(knowledgeBaseID: String, request: CloudKnowledgeCreateRunRequest) async throws -> CloudKnowledgePublicationRun
    func publicationRun(id: String) async throws -> CloudKnowledgePublicationRun
    func appendOperations(runID: String, request: CloudKnowledgeOperationBatchRequest) async throws -> CloudKnowledgeOperationBatchResponse
    func validate(runID: String) async throws -> CloudKnowledgeValidationResult
    func rebase(runID: String, request: CloudKnowledgeRebaseRequest) async throws -> CloudKnowledgePublicationRun
    func commit(runID: String) async throws -> CloudKnowledgeCommitResult
    func abandon(runID: String) async throws
    func search(knowledgeBaseID: String, channel: CloudKnowledgeSearchChannel, request: CloudKnowledgeSearchRequest) async throws -> CloudKnowledgeSearchResponse
}

public struct CloudKnowledgeAPIClient: CloudKnowledgeAPI, Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let credentials: any CloudKnowledgeCredentialProvider
    private let refreshRejectedToken: (@Sendable (String) async throws -> String)?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider(), refreshRejectedToken: (@Sendable (String) async throws -> String)? = nil) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials; self.refreshRejectedToken = refreshRejectedToken
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.keyEncodingStrategy = .convertToSnakeCase; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .custom { codingPath in
            let raw = codingPath.last?.stringValue ?? ""
            let parts = raw.split(separator: "_")
            guard parts.count > 1 else { return CloudKnowledgeCodingKey(raw) }
            let transformed = parts.enumerated().map { index, part -> String in
                if index == 0 { return String(part) }
                if part.lowercased() == "id" { return "ID" }
                if part.lowercased() == "ids" { return "IDs" }
                return part.prefix(1).uppercased() + part.dropFirst()
            }.joined()
            return CloudKnowledgeCodingKey(transformed)
        }
        self.decoder = decoder
    }

    public func createPublicationRun(knowledgeBaseID: String, request: CloudKnowledgeCreateRunRequest) async throws -> CloudKnowledgePublicationRun { try await send(Route.createRun(knowledgeBaseID).path, method: "POST", body: request) }
    public func publicationRun(id: String) async throws -> CloudKnowledgePublicationRun { try await send(Route.run(id).path) }
    public func appendOperations(runID: String, request: CloudKnowledgeOperationBatchRequest) async throws -> CloudKnowledgeOperationBatchResponse { try await send(Route.operations(runID).path, method: "POST", body: request) }
    public func validate(runID: String) async throws -> CloudKnowledgeValidationResult { try await send(Route.validate(runID).path, method: "POST", body: EmptyBody()) }
    public func rebase(runID: String, request: CloudKnowledgeRebaseRequest) async throws -> CloudKnowledgePublicationRun { try await send(Route.rebase(runID).path, method: "POST", body: request) }
    public func commit(runID: String) async throws -> CloudKnowledgeCommitResult { try await send(Route.commit(runID).path, method: "POST", body: EmptyBody()) }
    public func abandon(runID: String) async throws { let _: EmptyResponse = try await send(Route.abandon(runID).path, method: "POST", body: EmptyBody()) }
    public func search(knowledgeBaseID: String, channel: CloudKnowledgeSearchChannel, request: CloudKnowledgeSearchRequest) async throws -> CloudKnowledgeSearchResponse { try await send(Route.search(knowledgeBaseID, channel).path, method: "POST", body: request) }

    private enum Route {
        case createRun(String), run(String), operations(String), validate(String), rebase(String), commit(String), abandon(String), search(String, CloudKnowledgeSearchChannel)
        var path: String {
            switch self {
            case .createRun(let id): return "knowledge-bases/\(id)/publication-runs"
            case .run(let id): return "publication-runs/\(id)"
            case .operations(let id): return "publication-runs/\(id)/operations:batch"
            case .validate(let id): return "publication-runs/\(id)/validate"
            case .rebase(let id): return "publication-runs/\(id)/rebase"
            case .commit(let id): return "publication-runs/\(id)/commit"
            case .abandon(let id): return "publication-runs/\(id)/abandon"
            case .search(let id, let channel):
                let suffix = switch channel { case .recentContext: "recent-context"; case .knowledgeContext: "knowledge-context"; case .writeAssist: "write-assist"; case .answer: "answer" }
                return "knowledge-bases/\(id)/search/\(suffix)"
            }
        }
    }

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {}
    private struct Envelope<T: Decodable>: Decodable { var data: T }

    private func send<T: Decodable>(_ path: String, method: String = "GET") async throws -> T { try await send(path, method: method, bodyData: nil) }
    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T { try await send(path, method: method, bodyData: try encoder.encode(body)) }
    private func send<T: Decodable>(_ path: String, method: String, bodyData: Data?) async throws -> T {
        let root = baseURL.appendingPathComponent("api/v2/", isDirectory: true)
        guard let url = URL(string: path, relativeTo: root)?.absoluteURL else { throw CloudKnowledgeError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let initialToken = try await credentials.accessToken()
        request.setValue("Bearer \(initialToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await transport.data(for: request)
        guard var http = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }
        if http.statusCode == 401, let refreshRejectedToken {
            let refreshedToken = try await refreshRejectedToken(initialToken)
            request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await transport.data(for: request)
            guard let retriedHTTP = response as? HTTPURLResponse else { throw CloudKnowledgeError.invalidResponse }
            http = retriedHTTP
        }
        if http.statusCode == 401 { throw CloudKnowledgeError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
        if T.self == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! T }
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) { return envelope.data }
        if let value = try? decoder.decode(T.self, from: data) { return value }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        throw CloudKnowledgeError.invalidResponse
    }

    private static func error(status: Int, data: Data) -> CloudKnowledgeError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = object?["code"] as? String ?? (object?["error"] as? [String: Any])?["code"] as? String
        let message = object?["message"] as? String ?? object?["msg"] as? String ?? (object?["error"] as? [String: Any])?["message"] as? String ?? "请求失败（\(status)）"
        let currentSequence = object?["current_sequence"] as? Int ?? (object?["error"] as? [String: Any])?["current_sequence"] as? Int
        switch code {
        case "publication_conflict": return .publicationConflict(currentSequence: currentSequence)
        case "search_before_write_required": return .searchBeforeWriteRequired
        case "search_context_not_relevant": return .searchContextNotRelevant
        case "search_context_stale": return .searchContextStale
        default: return status == 409 ? .publicationConflict(currentSequence: currentSequence) : .server(status: status, code: code, message: message)
        }
    }
}
