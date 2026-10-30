import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AgentHTTPProxyError: Error, LocalizedError {
    case invalidAddress
    public var errorDescription: String? { "HTTP 代理地址无效，请使用 http://主机:端口；不支持内嵌账号密码。" }
}

public enum AgentHTTPProxy {
    public static func configuration(proxyURLString: String) throws -> URLSessionConfiguration {
        guard let url = URL(string: proxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "http", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", (1...65535).contains(url.port ?? 80) else {
            throw AgentHTTPProxyError.invalidAddress
        }
        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": url.port ?? 80,
            "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": url.port ?? 80
        ]
        return configuration
    }

    static func session(proxyURLString: String?) throws -> URLSession {
        guard let proxyURLString else { return .shared }
        return URLSession(configuration: try configuration(proxyURLString: proxyURLString))
    }
}
