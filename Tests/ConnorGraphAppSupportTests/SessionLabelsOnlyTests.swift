import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Test func legacySessionStatusIsNotDecodedOrEncoded() throws {
    let data = Data(#"{"kind":"chat","labels":[{"id":"project"}],"status":{"invalid":true}}"#.utf8)
    let governance = try JSONDecoder().decode(AgentSessionGovernanceMetadata.self, from: data)
    #expect(governance.labels.map(\.id) == ["project"])
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(governance)) as? [String: Any])
    #expect(json["status"] == nil)
}

@Test func oldStatusDefinitionsAreIgnoredWhileLabelsRemain() throws {
    let data = Data(#"{"statuses":{"invalid":true},"labels":[{"id":"project","name":"Project","colorName":"green"}]}"#.utf8)
    let config = try JSONDecoder().decode(AppSessionGovernanceConfig.self, from: data)
    #expect(config.labels.map(\.id) == ["project"])
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    #expect(json["statuses"] == nil)
}
