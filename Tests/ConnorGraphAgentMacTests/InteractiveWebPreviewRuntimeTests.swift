import Testing
@testable import ConnorGraphAgentMac

struct InteractiveWebPreviewRuntimeTests {
    @Test func sandboxPolicyDeniesNetworkAndEmbedding() {
        #expect(InteractiveWebPreviewRuntime.contentSecurityPolicy.contains("connect-src 'none'"))
        #expect(InteractiveWebPreviewRuntime.contentSecurityPolicy.contains("frame-ancestors 'none'"))
        #expect(InteractiveWebPreviewRuntime.scheme != "http")
        #expect(InteractiveWebPreviewRuntime.scheme != "https")
    }
}
