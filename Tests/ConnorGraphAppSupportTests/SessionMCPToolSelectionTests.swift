import Foundation
import Testing
import ConnorGraphAppSupport

@Test func sessionMCPToolSelectionRoundTripsAndRemainsBackwardCompatible() throws {
    let selected = AppSessionStateSnapshot(
        sessionID: "selected",
        allowedMCPToolNames: ["mcp__deepwiki__read_wiki_structure"]
    )
    let decoded = try JSONDecoder().decode(
        AppSessionStateSnapshot.self,
        from: JSONEncoder().encode(selected)
    )
    #expect(decoded.allowedMCPToolNames == ["mcp__deepwiki__read_wiki_structure"])

    let legacyJSON = #"{"schemaVersion":1,"sessionID":"legacy","updatedAt":0}"#
    let legacy = try JSONDecoder().decode(
        AppSessionStateSnapshot.self,
        from: Data(legacyJSON.utf8)
    )
    #expect(legacy.allowedMCPToolNames == nil)
}
