import Testing
import ConnorGraphCore
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

    @Test func layoutStabilizerIgnoresTinyDeltas() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        let current = MailHTMLBodyLayout(mode: .inline, height: 300, documentHeight: 286)
        #expect(stabilizer.stabilizedLayout(current: current, measuredDocumentHeight: 286) == nil)
    }

    @Test func layoutStabilizerClampsMinimumForInlineContent() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        let current = MailHTMLBodyLayout(mode: .inline, height: 500, documentHeight: 10)
        let layout = stabilizer.stabilizedLayout(current: current, measuredDocumentHeight: 10)
        #expect(layout == MailHTMLBodyLayout(mode: .inline, height: 200, documentHeight: 10))
    }

    @Test func layoutStabilizerKeepsShortHTMLInline() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        let current = MailHTMLBodyLayout(mode: .inline, height: 300, documentHeight: 500)
        let layout = stabilizer.stabilizedLayout(current: current, measuredDocumentHeight: 500)
        #expect(layout == MailHTMLBodyLayout(mode: .inline, height: 512, documentHeight: 500))
    }

    @Test func layoutStabilizerCapsLongHTMLWithScrollableViewport() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        let current = MailHTMLBodyLayout(mode: .inline, height: 500, documentHeight: 500)
        let layout = stabilizer.stabilizedLayout(current: current, measuredDocumentHeight: 20_000)
        #expect(layout == MailHTMLBodyLayout(mode: .scrollable, height: 640, documentHeight: 20_000))
    }

    @Test func layoutStabilizerKeepsBoundaryHTMLInline() {
        let stabilizer = MailHTMLBodyHeightStabilizer()
        let current = MailHTMLBodyLayout(mode: .inline, height: 500, documentHeight: 500)
        let boundaryHeight = stabilizer.inlineHeightLimit - stabilizer.bottomPadding
        let layout = stabilizer.stabilizedLayout(current: current, measuredDocumentHeight: boundaryHeight)
        guard let layout else {
            Issue.record("Expected boundary-height HTML to produce an inline layout update")
            return
        }
        #expect(layout.mode == .inline)
        #expect(abs(layout.height - stabilizer.inlineHeightLimit) < 0.001)
        #expect(abs(layout.documentHeight - boundaryHeight) < 0.001)
    }

    @Test func mailBodyLoadGateRejectsStaleMessageResult() {
        var gate = MailBodyLoadRequestGate()
        let first = gate.begin(messageID: MailMessageID(rawValue: "message-a"))
        let second = gate.begin(messageID: MailMessageID(rawValue: "message-b"))

        #expect(!gate.shouldCommit(first))
        #expect(gate.shouldCommit(second))
    }

    @Test func mailHTMLBodyUsesPageScrollingPolicy() {
        let policy = MailHTMLBodyScrollPolicy.pageScrolling

        #expect(!policy.isInternalScrollingEnabled)
        #expect(policy.forwardsWheelEventsToParent)
    }
}
