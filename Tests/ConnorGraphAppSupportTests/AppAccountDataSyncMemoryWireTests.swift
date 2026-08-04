import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Account Sync Memory Wire")
struct AppAccountDataSyncMemoryWireTests {
    @Test func l2StatementWireAlwaysEmitsOptionalFieldsAsNull() throws {
        let statement = MemoryOSStatement(
            id: "s1",
            subjectID: "e1",
            predicate: "knows",
            objectID: nil,
            text: "hello",
            committedAt: Date(timeIntervalSince1970: 0)
        )
        let wire = SyncMemoryL2Statement(statement)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"objectId\":null"))
        #expect(json.contains("\"sourceArtifactId\":null"))
    }

    @Test func l4RelationWireAlwaysEmitsOptionalFieldsAsNull() throws {
        let relation = MemoryOSEntityStatement(
            id: "r1",
            entityID: "e1",
            predicate: .relatedTo,
            objectEntityID: nil,
            text: "",
            committedAt: Date(timeIntervalSince1970: 0)
        )
        let wire = SyncMemoryL4Relation(relation)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"objectId\":null"))
        #expect(json.contains("\"sourceArtifactId\":null"))
    }

    @Test func l2StatementWireDecodesPayloadMissingOptionalFields() throws {
        let json = """
        {"id":"s1","subjectId":"e1","predicate":"knows","text":"hello",
         "factType":"other","assertionKind":"observed","confidence":0.5,
         "committedAt":"2026-08-05T00:00:00Z","evidenceSpanIdsJson":"[]",
         "metadataJson":"{}"}
        """
        let wire = try JSONDecoder().decode(SyncMemoryL2Statement.self, from: Data(json.utf8))
        #expect(wire.objectId == nil)
        #expect(wire.sourceArtifactId == nil)
        #expect(wire.makeStatement().text == "hello")
    }
}
