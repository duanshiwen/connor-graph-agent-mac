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

    @Test func heightStabilizerIgnoresTinyDeltas() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        #expect(stabilizer.stabilizedHeight(current: 300, measuredDocumentHeight: 286) == nil)
    }

    @Test func heightStabilizerClampsMinimum() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        #expect(stabilizer.stabilizedHeight(current: 500, measuredDocumentHeight: 10) == 200)
    }

    @Test func heightStabilizerClampsMaximum() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        #expect(stabilizer.stabilizedHeight(current: 500, measuredDocumentHeight: 20_000) == 8_000)
    }

    @Test func heightStabilizerAcceptsMeaningfulGrowth() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        #expect(stabilizer.stabilizedHeight(current: 300, measuredDocumentHeight: 500) == 512)
    }
}
