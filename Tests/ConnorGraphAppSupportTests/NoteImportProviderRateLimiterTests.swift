import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Note import provider rate limiter")
struct NoteImportProviderRateLimiterTests {
    @Test("Limits providers independently")
    func isolatesProviders() async {
        let limiter = NoteImportProviderRateLimiter(); let a = NoteImportProviderKey(connection: "a", provider: "p", model: "m"); let b = NoteImportProviderKey(connection: "b", provider: "p", model: "m")
        await limiter.configure(.init(maxConcurrent: 1), for: a); await limiter.configure(.init(maxConcurrent: 1), for: b)
        #expect(await limiter.acquire(a) == nil); #expect(await limiter.acquire(a) != nil); #expect(await limiter.acquire(b) == nil)
        await limiter.release(a); #expect(await limiter.acquire(a) == nil)
    }

    @Test("Honors retry after without blocking other providers")
    func honorsRetryAfter() async {
        let limiter = NoteImportProviderRateLimiter(); let now = Date(timeIntervalSince1970: 100); let a = NoteImportProviderKey(connection: "a", provider: "p", model: "m"); let b = NoteImportProviderKey(connection: "b", provider: "p", model: "m")
        await limiter.block(a, retryAfter: 12, now: now)
        #expect(await limiter.acquire(a, now: now) == 12); #expect(await limiter.acquire(b, now: now) == nil)
    }

    @Test("Retry policy uses retry after and full jitter exponential ceilings")
    func retryPolicy() {
        let policy = NoteImportRetryPolicy(maxAttempts: 4, initialDelay: 2, maximumDelay: 10)
        #expect(policy.delay(attempt: 3, random: 0.5) == 4)
        #expect(policy.delay(attempt: 9, retryAfter: 30) == 10)
        #expect(NoteImportProviderFailure.transient("offline").isRetryable)
        #expect(!NoteImportProviderFailure.contextExceeded.isRetryable)
    }
}
