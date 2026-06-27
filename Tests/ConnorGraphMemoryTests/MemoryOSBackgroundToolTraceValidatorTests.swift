import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Tool Trace Validator Tests")
struct MemoryOSBackgroundToolTraceValidatorTests {
    @Test func warnsWhenL1KnowledgeOutputsL4WithoutSearchTrace() throws {
        let artifact = #"{"operationalEntities":[],"operationalStatements":[],"evidenceSpans":[],"knowledgeCandidates":[],"conceptEntities":[{"id":"concept-1","name":"Memory OS"}],"conceptRelations":[],"promotionDecisions":[],"warnings":[],"confidence":0.8,"metadata":{}}"#

        let result = MemoryOSBackgroundToolTraceValidator(mode: .warning).validate(
            schemaName: "MemoryOSL1UnifiedProjectionOutput",
            rawArtifactJSON: artifact,
            toolCalls: []
        )

        #expect(result.accepted)
        #expect(result.issues.contains { $0.code == "missing_l1_knowledge_search_trace" && $0.severity == "warning" })
    }

    @Test func hardRejectsWhenConfiguredAndL2AcceptedKnowledgeHasNoSearchTrace() throws {
        let artifact = #"{"knowledgeCandidates":[{"id":"k1","signalAssessment":{"signalQualityAccepted":true,"reuseScopeAccepted":true,"noveltyAccepted":true,"structurabilityAccepted":true}}],"conceptEntities":[],"conceptRelations":[],"warnings":[],"metadata":{}}"#

        let result = MemoryOSBackgroundToolTraceValidator(mode: .hardReject).validate(
            schemaName: "MemoryOSKnowledgeExtractionOutput",
            rawArtifactJSON: artifact,
            toolCalls: []
        )

        #expect(result.accepted == false)
        #expect(result.issues.contains { $0.code == "missing_l2_knowledge_search_trace" && $0.severity == "error" })
    }

    @Test func warnsWhenHighRiskL4RelationHasNoSearchTrace() throws {
        let artifact = #"{"knowledgeCandidates":[],"conceptEntities":[{"id":"a"},{"id":"b"}],"conceptRelations":[{"id":"rel-1","predicate":"SAME_AS","subjectLocalID":"a","objectLocalID":"b"}],"warnings":[],"metadata":{}}"#
        let expand = MemoryOSBackgroundToolCallRecord(
            id: "tool-1",
            runID: "run-1",
            iteration: 1,
            toolName: "memory_os_expand_l4",
            argumentsJSON: #"{"entity_id":"a"}"#,
            status: .succeeded
        )

        let result = MemoryOSBackgroundToolTraceValidator(mode: .warning).validate(
            schemaName: "MemoryOSKnowledgeExtractionOutput",
            rawArtifactJSON: artifact,
            toolCalls: [expand]
        )

        #expect(result.accepted)
        #expect(result.issues.contains { $0.code == "missing_high_risk_l4_relation_search_trace" && $0.severity == "warning" })
    }

    @Test func acceptsWhenRequiredSearchTraceExists() throws {
        let artifact = #"{"knowledgeCandidates":[{"id":"k1","signalAssessment":{"signalQualityAccepted":true,"reuseScopeAccepted":true,"noveltyAccepted":true,"structurabilityAccepted":true}}],"conceptEntities":[],"conceptRelations":[],"warnings":[],"metadata":{}}"#
        let toolCall = MemoryOSBackgroundToolCallRecord(
            id: "tool-1",
            runID: "run-1",
            iteration: 1,
            toolName: "memory_os_search",
            argumentsJSON: #"{"query":"memory"}"#,
            status: .succeeded
        )

        let result = MemoryOSBackgroundToolTraceValidator(mode: .hardReject).validate(
            schemaName: "MemoryOSKnowledgeExtractionOutput",
            rawArtifactJSON: artifact,
            toolCalls: [toolCall]
        )

        #expect(result.accepted)
        #expect(result.issues.isEmpty)
    }
}
