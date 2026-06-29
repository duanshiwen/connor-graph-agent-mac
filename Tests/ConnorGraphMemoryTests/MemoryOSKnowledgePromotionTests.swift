import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func knowledgePromotionRejectsHighConfidenceOperationalFact() throws {
    let candidate = MemoryOSKnowledgeCandidate(
        title: "张三喜欢吃杨梅",
        claim: "张三喜欢吃杨梅。",
        knowledgeType: "fact",
        scope: "personal",
        domain: "personal-preference",
        signalAssessment: MemoryOSKnowledgeSignalAssessment(
            signalQualityAccepted: false,
            reuseScopeAccepted: false,
            noveltyAccepted: true,
            structurabilityAccepted: true,
            reasons: ["Personal preference is an operational fact, not reusable knowledge."]
        ),
        confidence: 0.99,
        evidenceStatementIDs: ["stmt-fact-1"],
        relatedEntityNames: ["person-zhangsan"]
    )

    let decision = MemoryOSKnowledgePromotionPolicy().evaluate(candidate)

    #expect(!decision.accepted)
    #expect(decision.rejectedDimensions.contains(.signalQuality))
    #expect(decision.rejectedDimensions.contains(.reuseScope))
}

@Test func knowledgePromotionAcceptsReusableStructuredTheoryClaim() throws {
    let candidate = MemoryOSKnowledgeCandidate(
        title: "供需弹性空间与参数变化关系",
        claim: "在特定约束下，供需弹性空间会随着某参数变化而改变。",
        category: "economics",
        knowledgeType: "theory",
        scope: "general",
        domain: "economics",
        workObjectID: "economics-knowledge-base",
        signalAssessment: MemoryOSKnowledgeSignalAssessment(
            signalQualityAccepted: true,
            reuseScopeAccepted: true,
            noveltyAccepted: true,
            structurabilityAccepted: true,
            reasons: ["Reusable economics theory claim with explicit concept entities."]
        ),
        confidence: 0.86,
        evidenceStatementIDs: ["stmt-theory-1"],
        evidenceSpanIDs: ["span-theory-1"],
        relatedEntityNames: ["concept-supply-demand-elasticity", "parameter-x"],
        metadata: ["related_object_names": "Supply and demand elasticity, Parameter"]
    )

    let decision = MemoryOSKnowledgePromotionPolicy().evaluate(candidate)
    let belief = try #require(MemoryOSKnowledgePromotionPolicy().makeKnowledgeBelief(from: candidate, decision: decision, sourceArtifactID: "artifact-knowledge", now: Date(timeIntervalSince1970: 10)))

    #expect(decision.accepted)
    #expect(decision.rejectedDimensions.isEmpty)
    #expect(belief.statement == candidate.claim)
    #expect(belief.domain == "economics")
    #expect(belief.relatedObjectNames == "Supply and demand elasticity, Parameter")
}

@Test func knowledgePromotionRejectsAcceptedSignalsWithoutStructure() throws {
    let candidate = MemoryOSKnowledgeCandidate(
        title: "未分类洞见",
        claim: "这是一个看似有用但无法归类的洞见。",
        signalAssessment: MemoryOSKnowledgeSignalAssessment(
            signalQualityAccepted: true,
            reuseScopeAccepted: true,
            noveltyAccepted: true,
            structurabilityAccepted: false,
            reasons: ["Missing discipline domain."]
        ),
        confidence: 0.8,
        evidenceStatementIDs: ["stmt-1"]
    )

    let decision = MemoryOSKnowledgePromotionPolicy().evaluate(candidate)

    #expect(!decision.accepted)
    #expect(decision.rejectedDimensions.contains(.structurability))
    #expect(MemoryOSKnowledgePromotionPolicy().makeKnowledgeBelief(from: candidate, decision: decision) == nil)
}
