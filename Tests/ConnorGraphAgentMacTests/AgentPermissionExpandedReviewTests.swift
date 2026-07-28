import Foundation
import Testing

@Suite("Agent Permission Expanded Review Tests")
struct AgentPermissionExpandedReviewTests {
    @Test func expandedMailBodyHasItsOwnBoundedScrollableRegion() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatPermissionRequestCard.swift"),
            encoding: .utf8
        )

        #expect(source.contains("ScrollView(.vertical)"))
        #expect(source.contains(".frame(minHeight: 180, maxHeight: 420)"))
        #expect(source.contains(".scrollIndicators(.visible)"))
        #expect(source.contains(".layoutPriority(1)"))
    }
}
