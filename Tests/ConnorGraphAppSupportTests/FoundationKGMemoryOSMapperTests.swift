import Foundation
import Testing
import ConnorGraphAppSupport

@Test func foundationKGMapperMapsNodeToNamespacedL4Entity() throws {
    let node = FoundationKGNodeRecord(
        id: "Q1000",
        kind: "entity",
        package: "concepts",
        labels: ["en": "Example", "zh-hans": "示例"],
        descriptions: ["en": "An example entity"],
        aliases: ["en": ["Sample"], "zh-hans": ["样例"]],
        sitelinks: ["enwiki": "Example"],
        salienceScore: 8.0,
        source: "wikidata"
    )

    let entity = FoundationKGMemoryOSMapper.mapEntity(
        node,
        supplementalAliases: ["示例实体"],
        builtAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(entity.id == "wikidata:Q1000")
    #expect(entity.stableKey == "wikidata:Q1000")
    #expect(entity.entityType == "wikidata_entity")
    #expect(entity.name == "示例")
    #expect(entity.summary == "An example entity")
    #expect(entity.aliases.contains("Sample"))
    #expect(entity.aliases.contains("样例"))
    #expect(entity.aliases.contains("示例实体"))
    #expect(entity.metadata["builtin_dataset"] == FoundationKGMemoryOSMapper.builtinDatasetID)
    #expect(entity.metadata["wikidata_id"] == "Q1000")
}

@Test func foundationKGMapperMapsResolvedEdgeToStatement() throws {
    let edge = FoundationKGEdgeRecord(sourceID: "Q1000", predicate: "P31", targetID: "Q5", targetKind: "entity", value: nil, source: "wikidata")
    let statement = FoundationKGMemoryOSMapper.mapEdgeStatement(
        edge,
        sourceName: "Example",
        propertyName: "instance of",
        targetName: "human",
        targetExists: true,
        builtAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(statement?.entityID == "wikidata:Q1000")
    #expect(statement?.predicate == .instanceOf)
    #expect(statement?.metadata["predicate"] == "P31")
    #expect(statement?.objectEntityID == "wikidata:Q5")
    #expect(statement?.text == "Example -- instance of --> human")
    #expect(statement?.metadata["target_resolution"] == "resolved")
}

@Test func foundationKGMapperMapsExternalIDToLiteralStatement() throws {
    let externalID = FoundationKGExternalIDRecord(nodeID: "Q1000", property: "P646", value: "/m/example", source: "wikidata")
    let statement = FoundationKGMemoryOSMapper.mapExternalIDStatement(
        externalID,
        sourceName: "Example",
        propertyName: "Freebase ID",
        builtAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(statement.entityID == "wikidata:Q1000")
    #expect(statement.predicate == .sameAs)
    #expect(statement.metadata["predicate"] == "P646")
    #expect(statement.objectEntityID == nil)
    #expect(statement.text == "Example -- Freebase ID --> /m/example")
    #expect(statement.metadata["statement_kind"] == "external_id")
    #expect(statement.metadata["external_id_value"] == "/m/example")
}
