import Foundation

public struct CalendarCalDAVHTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: String

    public init(method: String, url: URL, headers: [String: String] = [:], body: String = "") {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public var redactedDescription: String {
        var redactedHeaders = headers
        if redactedHeaders["Authorization"] != nil { redactedHeaders["Authorization"] = "<redacted>" }
        return "\(method) \(url.absoluteString) headers=\(redactedHeaders) bodyBytes=\(body.utf8.count)"
    }
}

public struct CalendarCalDAVHTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var body: String
    public var headers: [String: String]

    public init(statusCode: Int, body: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

public enum CalendarCalDAVHTTPError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case unexpectedStatus(Int)
    case invalidResponse
}

public protocol CalendarCalDAVHTTPTransport: Sendable {
    func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse
}

public struct URLSessionCalDAVHTTPTransport: CalendarCalDAVHTTPTransport {
    public init() {}

    public func send(_ request: CalendarCalDAVHTTPRequest) async throws -> CalendarCalDAVHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        if !request.body.isEmpty { urlRequest.httpBody = Data(request.body.utf8) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw CalendarCalDAVHTTPError.invalidResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { partial, pair in
            if let key = pair.key as? String { partial[key] = String(describing: pair.value) }
        }
        return CalendarCalDAVHTTPResponse(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "", headers: headers)
    }
}

public struct CalendarCalDAVHTTPClient: Sendable {
    private let transport: any CalendarCalDAVHTTPTransport

    public init(transport: any CalendarCalDAVHTTPTransport = URLSessionCalDAVHTTPTransport()) {
        self.transport = transport
    }

    public func propfind(url: URL, depth: String, body: String, credential: String?) async throws -> CalendarCalDAVHTTPResponse {
        try await send(method: "PROPFIND", url: url, depth: depth, body: body, credential: credential)
    }

    public func report(url: URL, depth: String, body: String, credential: String?) async throws -> CalendarCalDAVHTTPResponse {
        try await send(method: "REPORT", url: url, depth: depth, body: body, credential: credential)
    }

    private func send(method: String, url: URL, depth: String, body: String, credential: String?) async throws -> CalendarCalDAVHTTPResponse {
        var headers: [String: String] = [
            "Depth": depth,
            "Content-Type": "application/xml; charset=utf-8",
            "Accept": "application/xml,text/xml,text/calendar,*/*"
        ]
        if let credential, !credential.isEmpty { headers["Authorization"] = "Bearer \(credential)" }
        let response = try await transport.send(CalendarCalDAVHTTPRequest(method: method, url: url, headers: headers, body: body))
        try validate(response)
        return response
    }

    private func validate(_ response: CalendarCalDAVHTTPResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw CalendarCalDAVHTTPError.unauthorized
        case 403: throw CalendarCalDAVHTTPError.forbidden
        case 404: throw CalendarCalDAVHTTPError.notFound
        case 429: throw CalendarCalDAVHTTPError.rateLimited
        case 500..<600: throw CalendarCalDAVHTTPError.serverError(response.statusCode)
        default: throw CalendarCalDAVHTTPError.unexpectedStatus(response.statusCode)
        }
    }
}
