import Foundation
import Testing
@testable import ConnorGraphAgent

@Test func modelProxyConfiguresHTTPAndHTTPSWithoutChangingSharedSession() throws {
    let configuration = try AgentHTTPProxy.configuration(proxyURLString: " http://127.0.0.1:7890 ")
    #expect(configuration.connectionProxyDictionary?["HTTPProxy"] as? String == "127.0.0.1")
    #expect(configuration.connectionProxyDictionary?["HTTPSProxy"] as? String == "127.0.0.1")
    #expect(configuration.connectionProxyDictionary?["HTTPSPort"] as? Int == 7890)
    #expect(URLSessionAgentHTTPClient(proxyURLString: "http://127.0.0.1:7890").proxyURLString == "http://127.0.0.1:7890")
    #expect(URLSessionAgentSSEHTTPClient(proxyURLString: "http://127.0.0.1:7890").proxyURLString == "http://127.0.0.1:7890")
    for invalid in ["", "not a proxy", "socks5://localhost:1080", "http://user:password@localhost:7890", "http://localhost:0", "http://localhost:7890/path"] {
        #expect(throws: AgentHTTPProxyError.self) { try AgentHTTPProxy.configuration(proxyURLString: invalid) }
    }
}
