import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Agent Markdown image source policy")
struct AgentMarkdownImageSourcePolicyTests {
    @Test("Allows HTTPS remote images")
    func allowsHTTPS() {
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "https://example.com/a.png")?.host == "example.com")
    }

    @Test("Allows HTTP only for loopback hosts")
    func allowsLoopbackHTTPOnly() {
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "http://localhost:8080/a.png") != nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "http://127.0.0.1/a.png") != nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "http://[::1]/a.png") != nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "http://example.com/a.png") == nil)
    }

    @Test("Rejects unsafe schemes")
    func rejectsUnsafeSchemes() {
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "data:image/png;base64,AAAA") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "javascript:alert(1)") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "file:///etc/passwd") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "ftp://example.com/a.png") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "connor://open/agent-chat?session=x") == nil)
    }

    @Test("Rejects userinfo and missing hosts")
    func rejectsUserinfoAndMissingHosts() {
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "https://user:pass@example.com/a.png") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "https://user@example.com/a.png") == nil)
        #expect(AgentMarkdownImageSourcePolicy.remoteImageURL(source: "https:///a.png") == nil)
    }

    @Test("Resolves local-within-root and remote sources")
    func resolvesSources() {
        let root = URL(fileURLWithPath: "/tmp/root")
        #expect(AgentMarkdownImageSourcePolicy.resolvedSource(source: "file:///tmp/root/a.png", allowedRoot: root) == .local(URL(fileURLWithPath: "/tmp/root/a.png")))
        #expect(AgentMarkdownImageSourcePolicy.resolvedSource(source: "file:///tmp/outside/a.png", allowedRoot: root) == nil)
        #expect(AgentMarkdownImageSourcePolicy.resolvedSource(source: "https://example.com/a.png", allowedRoot: root) == .remote(URL(string: "https://example.com/a.png")!))
        #expect(AgentMarkdownImageSourcePolicy.resolvedSource(source: "http://example.com/a.png", allowedRoot: root) == nil)
    }

    @Test("Validates decoded image data before display")
    func validatesImageData() {
        let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        #expect(AgentMarkdownRemoteImagePolicy.validatedImageData(tinyPNG) != nil)

        #expect(AgentMarkdownRemoteImagePolicy.validatedImageData(Data("not an image".utf8)) == nil)
        #expect(AgentMarkdownRemoteImagePolicy.validatedImageData(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)) == nil)
        #expect(AgentMarkdownRemoteImagePolicy.validatedImageData(Data(count: AgentMarkdownRemoteImagePolicy.maxBytes + 1)) == nil)
    }
}
