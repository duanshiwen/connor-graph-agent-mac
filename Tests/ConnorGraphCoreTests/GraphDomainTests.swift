import Foundation
import Testing
import ConnorGraphCore

@Test func graphNodeSupportsTypedNode() throws {
    let node = GraphNode(
        id: "node-work-object-agent-os",
        type: .workObject,
        title: "Agent OS",
        summary: "Local-first agent operating system"
    )

    #expect(node.id == "node-work-object-agent-os")
    #expect(node.type == .workObject)
    #expect(node.title == "Agent OS")
    #expect(node.summary == "Local-first agent operating system")
    #expect(node.status == .active)
}

@Test func semanticEdgeConnectsSourceTargetAndRelation() throws {
    let edge = SemanticEdge(
        id: "edge-question-answer",
        sourceNodeID: "question-1",
        targetNodeID: "answer-1",
        relation: .answeredBy,
        fact: "Question 1 is answered by Answer 1"
    )

    #expect(edge.sourceNodeID == "question-1")
    #expect(edge.targetNodeID == "answer-1")
    #expect(edge.relation == .answeredBy)
    #expect(edge.fact == "Question 1 is answered by Answer 1")
}

@Test func semanticEdgeTemporalValidityUsesValidAndInvalidTime() throws {
    let validAt = Date(timeIntervalSince1970: 1_000)
    let invalidAt = Date(timeIntervalSince1970: 2_000)
    let edge = SemanticEdge(
        id: "edge-temporal",
        sourceNodeID: "person-shiwen",
        targetNodeID: "work-object-agent-os",
        relation: .worksOn,
        fact: "Shiwen works on Agent OS",
        validAt: validAt,
        invalidAt: invalidAt
    )

    #expect(edge.isActive(at: Date(timeIntervalSince1970: 999)) == false)
    #expect(edge.isActive(at: Date(timeIntervalSince1970: 1_500)) == true)
    #expect(edge.isActive(at: Date(timeIntervalSince1970: 2_000)) == false)
}

@Test func questionNodeCanBeAnsweredByAnswerNodeThroughSemanticEdge() throws {
    let question = GraphNode.question(id: "question-1", title: "How should memory work?")
    let answer = GraphNode.answer(id: "answer-1", title: "Use a graph-backed memory layer")
    let edge = SemanticEdge.answeredBy(questionID: question.id, answerID: answer.id)

    #expect(question.type == .question)
    #expect(answer.type == .answer)
    #expect(edge.sourceNodeID == question.id)
    #expect(edge.targetNodeID == answer.id)
    #expect(edge.relation == .answeredBy)
}

@Test func legacyStructuresAreTypedNodesNotSeparateStorageModels() throws {
    let workObject = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS")
    let decision = GraphNode.decision(id: "decision-native-mac", title: "Use SwiftUI")
    let procedure = GraphNode.procedure(id: "procedure-import", title: "Import legacy knowledge")
    let person = GraphNode.person(id: "person-shiwen", title: "诗闻")

    #expect(workObject.type == .workObject)
    #expect(decision.type == .decision)
    #expect(procedure.type == .procedure)
    #expect(person.type == .person)
}
