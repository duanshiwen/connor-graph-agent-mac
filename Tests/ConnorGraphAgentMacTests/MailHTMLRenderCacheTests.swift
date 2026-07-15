import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
struct MailHTMLRenderCacheTests {
    @Test func cachedPreparedHTMLIsIsolatedByMessageAndRemoteImagePolicy() {
        let cache = MailHTMLRenderCache(capacity: 8)
        let blocked = request(id: "message-a", html: "<p>Hello</p>", allowsRemoteImages: false)
        let allowed = request(id: "message-a", html: "<p>Hello</p>", allowsRemoteImages: true)
        let prepared = MailPreparedHTMLBodyPresentation(html: "prepared", blockedRemoteImageCount: 1)

        cache.insert(prepared, for: blocked)

        #expect(cache.value(for: blocked) == prepared)
        #expect(cache.value(for: allowed) == nil)
    }

    @Test func cacheUsesDeterministicLRUEviction() {
        let cache = MailHTMLRenderCache(capacity: 2)
        let first = request(id: "first", html: "1", allowsRemoteImages: false)
        let second = request(id: "second", html: "2", allowsRemoteImages: false)
        let third = request(id: "third", html: "3", allowsRemoteImages: false)
        let value = MailPreparedHTMLBodyPresentation(html: "prepared", blockedRemoteImageCount: 0)

        cache.insert(value, for: first)
        cache.insert(value, for: second)
        _ = cache.value(for: first)
        cache.insert(value, for: third)

        #expect(cache.cachedRequests == [first, third])
        #expect(cache.count == 2)
    }

    @Test func mailConfigurationsShareDedicatedPoolAndDisableJavaScript() {
        let provider = MailWebViewConfigurationProvider()
        let first = provider.makeConfiguration()
        let second = provider.makeConfiguration()

        #expect(provider.sharesMailProcessPool(first, second))
        #expect(first.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(second.defaultWebpagePreferences.allowsContentJavaScript == false)
    }

    private func request(id: String, html: String, allowsRemoteImages: Bool) -> MailHTMLSanitizationRequest {
        MailHTMLSanitizationRequest(
            messageID: MailMessageID(rawValue: id),
            html: html,
            allowsRemoteImages: allowsRemoteImages
        )
    }
}
