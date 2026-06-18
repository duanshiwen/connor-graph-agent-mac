import Foundation

public enum MCPHTTPClientTransportError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidEndpoint(String)
    case invalidHeaderName(String)
    case invalidHeaderValue(String)
    case invalidHTTPResponse
    case httpStatus(Int, String)
    case streamingResponseUnsupported
    case invalidResponseBody(String)

    public var description: String {
        switch self {
        case .invalidEndpoint(let value): "invalidEndpoint: \(value)"
        case .invalidHeaderName(let value): "invalidHeaderName: \(value)"
        case .invalidHeaderValue(let value): "invalidHeaderValue: \(value)"
        case .invalidHTTPResponse: "invalidHTTPResponse"
        case .httpStatus(let status, let body): "httpStatus: \(status) \(body)"
        case .streamingResponseUnsupported: "streamingResponseUnsupported: request-scoped SSE responses are not enabled yet"
        case .invalidResponseBody(let message): "invalidResponseBody: \(message)"
        }
    }
}

/// MCP Streamable HTTP transport, currently supporting the JSON response path.
///
/// Commercial safety boundaries:
/// - Endpoint must be HTTPS unless it is loopback localhost for development.
/// - Secrets are accepted only as HTTP headers supplied by Connor's credential boundary.
/// - Query-string credentials are intentionally unsupported.
/// - Request-scoped SSE streaming responses fail closed until the runtime has explicit stream handling.
public struct MCPHTTPClientTransport: MCPClientTransport {
    public var endpointURL: URL
    public var headers: [String: String]
    public var timeoutInterval: TimeInterval

    public init(endpointURL: URL, headers: [String: String] = [:], timeoutInterval: TimeInterval = 30) throws {
        try Self.validateEndpoint(endpointURL)
        try headers.forEach { try Self.validateHeader(name: $0.key, value: $0.value) }
        self.endpointURL = endpointURL
        self.headers = headers
        self.timeoutInterval = timeoutInterval
    }

    public func send(_ message: MCPJSONRPCMessage) async throws -> MCPJSONRPCMessage? {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONEncoder().encode(message)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPHTTPClientTransportError.invalidHTTPResponse
        }
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") {
            throw MCPHTTPClientTransportError.streamingResponseUnsupported
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MCPHTTPClientTransportError.httpStatus(httpResponse.statusCode, body)
        }
        guard message.id != nil else { return nil }
        do {
            return try JSONDecoder().decode(MCPJSONRPCMessage.self, from: data)
        } catch {
            throw MCPHTTPClientTransportError.invalidResponseBody(String(describing: error))
        }
    }

    public func close() async throws {}

    public static func validateEndpoint(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            throw MCPHTTPClientTransportError.invalidEndpoint(url.absoluteString)
        }
        guard url.user == nil, url.password == nil else {
            throw MCPHTTPClientTransportError.invalidEndpoint("Endpoint URL must not embed credentials")
        }
        if scheme == "https" { return }
        if scheme == "http", isLoopbackHost(host) { return }
        throw MCPHTTPClientTransportError.invalidEndpoint("HTTP MCP endpoints must use https unless they target localhost/loopback")
    }

    public static func validateHeader(name: String, value: String) throws {
        let headerNamePattern = #"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$"#
        guard name.range(of: headerNamePattern, options: .regularExpression) != nil else {
            throw MCPHTTPClientTransportError.invalidHeaderName(name)
        }
        guard !value.contains("\r"), !value.contains("\n") else {
            throw MCPHTTPClientTransportError.invalidHeaderValue(name)
        }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }
}
