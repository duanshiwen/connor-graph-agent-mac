import Foundation
import Testing
import ConnorGraphMemory

@Suite("Memory OS Knowledge Synthesis Draft Tests")
struct MemoryOSKnowledgeSynthesisDraftTests {
    @Test func adaptsL1KnowledgeDraftToUnifiedKnowledgeSynthesisDraft() throws {
        let l1 = MemoryOSL1UnifiedProjectionJobDraft(
            id: "l1-job",
            captureEventIDs: ["cap-1", "cap-2"],
            provenanceObjectIDs: ["prov-1"],
            sourceSpanIDs: ["span-1"],
            prompt: "L1 batch prompt",
            metadata: ["trigger": "count"]
        )

        let unified = MemoryOSKnowledgeSynthesisJobDraft(l1: l1)

        #expect(unified.id == "l1-job")
        #expect(unified.kind == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
        #expect(unified.source == .l1CaptureEvents)
        #expect(unified.artifactType == "memory_os_l1_unified_projection")
        #expect(unified.sourceRecordIDs == ["cap-1", "cap-2"])
        #expect(unified.evidenceSpanIDs == ["span-1"])
        #expect(unified.metadata["trigger"] == "count")
    }

    @Test func adaptsL2KnowledgeDraftToUnifiedKnowledgeSynthesisDraft() throws {
        let l2 = MemoryOSL2ToKnowledgeJobDraft(
            id: "l2-job",
            statementIDs: ["stmt-1"],
            evidenceSpanIDs: ["span-1"],
            prompt: "L2 batch prompt",
            metadata: ["trigger": "age"]
        )

        let unified = MemoryOSKnowledgeSynthesisJobDraft(l2: l2)

        #expect(unified.id == "l2-job")
        #expect(unified.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
        #expect(unified.source == .l2Statements)
        #expect(unified.artifactType == "memory_os_knowledge_extraction")
        #expect(unified.sourceRecordIDs == ["stmt-1"])
        #expect(unified.evidenceSpanIDs == ["span-1"])
        #expect(unified.metadata["trigger"] == "age")
    }
}
