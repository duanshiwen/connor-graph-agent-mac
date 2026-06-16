import XCTest
@testable import ConnorGraphAppSupport

final class AgentToolOutputDisplayPolicyTests: XCTestCase {
    func testSmallOutputIsDisplayedWithoutTruncation() {
        let policy = AgentToolOutputDisplayPolicy(previewCharacterLimit: 20)

        let display = policy.display(for: "hello")

        XCTAssertEqual(display.previewText, "hello")
        XCTAssertFalse(display.isTruncated)
        XCTAssertEqual(display.originalCharacterCount, 5)
    }

    func testLargeOutputIsTruncatedAtPreviewLimit() {
        let policy = AgentToolOutputDisplayPolicy(previewCharacterLimit: 5)

        let display = policy.display(for: "hello world")

        XCTAssertEqual(display.previewText, "hello")
        XCTAssertTrue(display.isTruncated)
        XCTAssertEqual(display.originalCharacterCount, 11)
        XCTAssertEqual(display.omittedCharacterCount, 6)
    }

    func testNilOutputUsesEmptyPreview() {
        let policy = AgentToolOutputDisplayPolicy(previewCharacterLimit: 5)

        let display = policy.display(for: nil)

        XCTAssertEqual(display.previewText, "")
        XCTAssertFalse(display.isTruncated)
        XCTAssertEqual(display.originalCharacterCount, 0)
    }
}
