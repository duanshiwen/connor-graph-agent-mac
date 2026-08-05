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

    @Test func l1CaptureWireAlwaysEmitsRetrievalTextAsNull() throws {
        let event = MemoryOSCaptureEvent(
            id: "c1",
            provenanceObjectID: "p1",
            eventType: "user",
            occurredAt: Date(timeIntervalSince1970: 0),
            retrievalText: nil
        )
        let wire = SyncL1Capture(event: event)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"retrievalText\":null"))
    }

    @Test func l0ProvenanceWireAlwaysEmitsRequiredFields() throws {
        let provenance = MemoryOSProvenanceObject(
            id: "p1",
            sourceType: .manual,
            sourceID: nil,
            title: "t",
            content: "c",
            contentHash: "h",
            occurredAt: Date(timeIntervalSince1970: 0),
            sessionID: nil,
            workObjectID: nil
        )
        let wire = SyncL0Provenance(provenance: provenance)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"sourceId\":\"\""))
        #expect(json.contains("\"sessionId\":null"))
        #expect(json.contains("\"workObjectId\":null"))
    }

    @Test func l0SpanWireAlwaysEmitsOffsetFields() throws {
        let span = MemoryOSProvenanceSpan(
            id: "sp1",
            provenanceObjectID: "p1",
            startOffset: nil,
            endOffset: nil,
            text: "hello"
        )
        let wire = SyncL0Span(span: span)
        let data = try JSONEncoder().encode(wire)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"startOffset\":0"))
        #expect(json.contains("\"endOffset\":0"))
    }
}
