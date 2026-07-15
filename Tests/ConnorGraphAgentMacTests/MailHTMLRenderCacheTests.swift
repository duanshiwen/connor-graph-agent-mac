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

    @Test func cacheEnforcesTotalByteCapacity() {
        let cache = MailHTMLRenderCache(capacity: 8, byteCapacity: 10)
        let first = request(id: "first", html: "first", allowsRemoteImages: false)
        let second = request(id: "second", html: "second", allowsRemoteImages: false)
        let oversized = request(id: "oversized", html: "oversized", allowsRemoteImages: false)

        cache.insert(MailPreparedHTMLBodyPresentation(html: "123456", blockedRemoteImageCount: 0), for: first)
        cache.insert(MailPreparedHTMLBodyPresentation(html: "abcdef", blockedRemoteImageCount: 0), for: second)
        cache.insert(MailPreparedHTMLBodyPresentation(html: "12345678901", blockedRemoteImageCount: 0), for: oversized)

        #expect(cache.cachedRequests == [second])
        #expect(cache.totalByteCount == 6)
    }

    @Test func presentationUpdateInvalidatesModelPreparedHTMLCache() {
        let model = MailFeatureModel(store: nil, preferencesStore: nil)
        let request = request(id: "message", html: "<p>Hello</p>", allowsRemoteImages: false)
        model.preparedHTMLCache.insert(
            MailPreparedHTMLBodyPresentation(html: "prepared", blockedRemoteImageCount: 0),
            for: request
        )
        #expect(model.preparedHTMLCache.count == 1)

        model.presentation = .empty

        #expect(model.preparedHTMLCache.count == 0)
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
