import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l2EntityMemorySplitsNamesForExactAliasLookup() {
    let names = MemoryOSL2EntityMemoryService.splitNames("《迟到的青春期》，迟到的青春期, Late Puberty、Manila Phase;康莱德；Conrad\n贫民窟")

    #expect(names == ["《迟到的青春期》", "迟到的青春期", "Late Puberty", "Manila Phase", "康莱德", "Conrad", "贫民窟"])
}

@Test func l2EntityMemoryFindsExactNameAndAliasWithoutInternalFields() throws {
    let service = MemoryOSL2EntityMemoryService(repository: InMemoryMemoryOSL2EntityMemoryRepository(
        entities: [
            MemoryOSL2StoredEntity(
                id: "node-project",
                name: "《迟到的青春期》",
                type: "work_object",
                aliases: ["迟到的青春期", "Late Puberty"],
                summary: "诗闻的纪录片项目。",
                statements: [
                    MemoryOSL2StoredStatement(
                        id: "stmt-1",
                        text: "《迟到的青春期》马尼拉一个月阶段的明确决策是：不去贫民窟。",
                        relation: "RELATED_TO",
                        connectedEntityName: "《迟到的青春期》马尼拉一个月阶段"
                    )
                ]
            )
        ]
    ))

    let result = try service.findEntities(MemoryOSL2FindEntitiesRequest(names: "Late Puberty"))

    #expect(result.searchedNames == ["Late Puberty"])
    #expect(result.matches.count == 1)
    #expect(result.matches[0].name == "《迟到的青春期》")
    #expect(result.matches[0].aliases == "迟到的青春期, Late Puberty")
    #expect(result.matches[0].type == "work_object")
    #expect(result.matches[0].statements == [MemoryOSL2StatementMemoryView(text: "《迟到的青春期》马尼拉一个月阶段的明确决策是：不去贫民窟。", relation: "RELATED_TO", connectedEntity: "《迟到的青春期》马尼拉一个月阶段")])
}

@Test func l2EntityMemoryUpdateDefaultsRelationAndPreservesNegativeDecisionMetadata() throws {
    let repository = InMemoryMemoryOSL2EntityMemoryRepository()
    let service = MemoryOSL2EntityMemoryService(repository: repository)

    let result = try service.updateEntities(MemoryOSL2UpdateEntitiesRequest(entities: [
        MemoryOSL2EntityUpdate(
            name: "《迟到的青春期》",
            type: "work_object",
            aliases: "迟到的青春期, Late Puberty",
            summary: "诗闻的纪录片项目。",
            statements: [
                MemoryOSL2StatementUpdate(
                    text: "《迟到的青春期》马尼拉一个月阶段的明确决策是：不去贫民窟。",
                    connectedEntity: "《迟到的青春期》马尼拉一个月阶段",
                    connectedEntityType: "work_object",
                    factType: "decision",
                    polarity: "exclude",
                    originalPhrase: "不去贫民窟"
                )
            ]
        )
    ]))

    #expect(result.accepted)
    #expect(result.updatedEntities[0].action == "created")
    #expect(result.updatedEntities[0].statementActions[0].action == "added")

    let stored = try repository.findEntities(matchingNames: ["迟到的青春期"])
    #expect(stored.count == 1)
    #expect(stored[0].statements[0].relation == "RELATED_TO")
    #expect(stored[0].statements[0].metadata["factType"] == "decision")
    #expect(stored[0].statements[0].metadata["polarity"] == "exclude")
    #expect(stored[0].statements[0].metadata["originalPhrase"] == "不去贫民窟")
}
