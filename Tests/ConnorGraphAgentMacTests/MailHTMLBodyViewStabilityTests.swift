import Testing
@testable import ConnorGraphAgentMac

@Suite("Mail HTML Body View Stability Tests")
struct MailHTMLBodyViewStabilityTests {
    @Test func sameHTMLDoesNotRequestReload() {
        var state = MailHTMLBodyLoadState()
        let firstDecision = state.shouldReload(html: "<p>Hello</p>")
        let secondDecision = state.shouldReload(html: "<p>Hello</p>")
        #expect(firstDecision)
        #expect(!secondDecision)
    }

    @Test func changedHTMLRequestsReload() {
        var state = MailHTMLBodyLoadState()
        let firstDecision = state.shouldReload(html: "<p>Hello</p>")
        let secondDecision = state.shouldReload(html: "<p>Hello<img src=\"https://example.com/a.png\"></p>")
        #expect(firstDecision)
        #expect(secondDecision)
    }
}
