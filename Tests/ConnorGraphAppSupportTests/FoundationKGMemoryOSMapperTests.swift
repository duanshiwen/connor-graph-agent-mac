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

@Test func foundationKGMapperMapsCommonWikidataPropertiesToControlledL4Predicates() throws {
    let cases: [(property: String, targetKind: String, expected: String)] = [
        ("P17", "entity", "LOCATED_IN"),
        ("P30", "entity", "LOCATED_IN"),
        ("P131", "entity", "LOCATED_IN"),
        ("P706", "entity", "LOCATED_IN"),
        ("P159", "entity", "HAS_LOCATION"),
        ("P276", "entity", "HAS_LOCATION"),
        ("P740", "entity", "HAS_LOCATION"),
        ("P625", "literal", "HAS_COORDINATE"),
        ("P50", "entity", "AUTHORED_BY"),
        ("P170", "entity", "CREATED_BY"),
        ("P176", "entity", "DEVELOPED_BY"),
        ("P178", "entity", "DEVELOPED_BY"),
        ("P112", "entity", "FOUNDED_BY"),
        ("P127", "entity", "OWNED_BY"),
        ("P921", "entity", "ABOUT"),
        ("P366", "entity", "USED_FOR"),
        ("P101", "entity", "FIELD_OF_WORK"),
        ("P106", "entity", "FIELD_OF_WORK"),
        ("P452", "entity", "IN_INDUSTRY"),
        ("P425", "entity", "FIELD_OF_WORK"),
        ("P856", "literal", "HAS_OFFICIAL_WEBSITE"),
        ("P646", "literal", "HAS_IDENTIFIER"),
        ("P244", "literal", "HAS_IDENTIFIER"),
        ("P214", "literal", "HAS_IDENTIFIER"),
        ("P227", "literal", "HAS_IDENTIFIER"),
        ("P213", "literal", "HAS_IDENTIFIER"),
        ("P345", "literal", "HAS_IDENTIFIER"),
        ("P1709", "literal", "HAS_IDENTIFIER"),
        ("P2888", "literal", "HAS_IDENTIFIER"),
        ("P463", "entity", "MEMBER_OF"),
        ("P460", "entity", "SAID_TO_BE_SAME_AS"),
        ("P461", "entity", "OPPOSITE_OF"),
        ("P2579", "entity", "STUDIED_BY"),
        ("P1269", "entity", "FACET_OF")
    ]

    for item in cases {
        let edge = FoundationKGEdgeRecord(sourceID: "Q1000", predicate: item.property, targetID: item.targetKind == "entity" ? "Q2000" : nil, targetKind: item.targetKind, value: item.targetKind == "literal" ? "literal-value" : nil, source: "wikidata")
        let statement = FoundationKGMemoryOSMapper.mapEdgeStatement(
            edge,
            sourceName: "Example",
            propertyName: item.property,
            targetName: item.targetKind == "entity" ? "Target" : nil,
            targetExists: item.targetKind == "entity",
            builtAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(statement?.predicate.rawValue == item.expected)
        #expect(statement?.metadata["predicate"] == item.property)
    }
}
