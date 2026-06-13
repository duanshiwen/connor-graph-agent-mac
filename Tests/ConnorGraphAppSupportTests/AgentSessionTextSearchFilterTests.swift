import XCTest
import ConnorGraphCore
@testable import ConnorGraphAppSupport

final class AgentSessionTextSearchFilterTests: XCTestCase {
    func testFilterMatchesSessionTitleCaseInsensitively() {
        let matching = AgentSession(title: "Browser Tabs Roadmap")
        let other = AgentSession(title: "Graph Memory Review")

        let result = AgentSessionTextSearchFilter().filter([matching, other], query: "browser")

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    func testFilterMatchesMessageContent() {
        var matching = AgentSession(title: "Untitled")
        matching.appendUserMessage("Please add toolbar search for sessions")
        let other = AgentSession(title: "Untitled")

        let result = AgentSessionTextSearchFilter().filter([matching, other], query: "toolbar")

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    func testFilterRequiresAllQueryTerms() {
        var matching = AgentSession(title: "Session Search")
        matching.appendAssistantMessage("Matches simple text across conversation content")
        var partial = AgentSession(title: "Session Search")
        partial.appendAssistantMessage("No matching body term")

        let result = AgentSessionTextSearchFilter().filter([matching, partial], query: "session content")

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    func testBlankQueryReturnsOriginalOrder() {
        let first = AgentSession(title: "First")
        let second = AgentSession(title: "Second")

        let result = AgentSessionTextSearchFilter().filter([first, second], query: "  \n ")

        XCTAssertEqual(result.map(\.id), [first.id, second.id])
    }
}
