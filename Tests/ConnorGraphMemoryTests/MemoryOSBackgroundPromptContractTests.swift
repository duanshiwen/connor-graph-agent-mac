import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Prompt Contract Tests")
struct MemoryOSBackgroundPromptContractTests {
    @Test func l1ToL2PromptRendersCaptureEventsAsJSONArray() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let events = [
            MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: now, tokenEstimate: 42, metadata: ["span_id": "span-1", "source_kind": "mail", "title": "Mail A", "content_preview": "User wants L1 cleared after successful processing."]),
            MemoryOSCaptureEvent(id: "cap-2", provenanceObjectID: "prov-2", eventType: "source_event", occurredAt: now.addingTimeInterval(60), tokenEstimate: 84, metadata: ["span_id": "span-2", "source_kind": "rss", "title": "RSS B", "content_preview": "Memory OS should preserve L0 as durable evidence."])
        ]

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: events)

        #expect(prompt.contains("\"l1_capture_events\""))
        #expect(prompt.contains("\"capture_event_id\" : \"cap-1\"") || prompt.contains("\"capture_event_id\": \"cap-1\""))
        #expect(prompt.contains("\"capture_event_id\" : \"cap-2\"") || prompt.contains("\"capture_event_id\": \"cap-2\""))
        #expect(prompt.contains("\"event_type\""))
        #expect(prompt.contains("\"source_kind\""))
        #expect(prompt.contains("\"provenance_object_id\""))
        #expect(prompt.contains("\"span_id\""))
        #expect(prompt.contains("\"occurred_at\""))
        #expect(prompt.contains("\"token_estimate\""))
        #expect(prompt.contains("\"metadata\""))
        #expect(prompt.range(of: "cap-1")!.lowerBound < prompt.range(of: "cap-2")!.lowerBound)
    }

    @Test func l2ToKnowledgePromptRendersStatementsAsJSONArray() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let statements = [
            MemoryOSStatement(id: "stmt-1", subjectID: "node-1", predicate: "prefers", text: "User prefers structured prompts.", confidence: 0.91, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"], metadata: ["processing_state": "pending"]),
            MemoryOSStatement(id: "stmt-2", subjectID: "node-2", predicate: "requires", text: "Knowledge promotion requires four-filter judgment.", confidence: 0.88, validAt: now, committedAt: now.addingTimeInterval(60), evidenceSpanIDs: ["span-2", "span-3"], metadata: ["domain": "knowledge-management"])
        ]

        let prompt = MemoryOSL2ToKnowledgePromptBuilder().prompt(for: statements)

        #expect(prompt.contains("\"l2_statements\""))
        #expect(prompt.contains("\"statement_id\" : \"stmt-1\"") || prompt.contains("\"statement_id\": \"stmt-1\""))
        #expect(prompt.contains("\"statement_id\" : \"stmt-2\"") || prompt.contains("\"statement_id\": \"stmt-2\""))
        #expect(prompt.contains("\"subject_id\""))
        #expect(prompt.contains("\"predicate\""))
        #expect(prompt.contains("\"text\""))
        #expect(prompt.contains("\"confidence\""))
        #expect(prompt.contains("\"committed_at\""))
        #expect(prompt.contains("\"evidence_span_ids\""))
        #expect(prompt.contains("\"metadata\""))
    }

    @Test func l1PromptStatesL1IsActiveBufferAndL0IsDurableEvidence() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L0 is the durable provenance layer"))
        #expect(prompt.contains("L1 is the active processing buffer"))
        #expect(prompt.contains("successful L1 unified projection"))
    }

    @Test func l1PromptDefinesDisciplinedFactExtractionWorkflow() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Read L1 events in chronological order"))
        #expect(prompt.contains("Extract candidate operational facts per event"))
        #expect(prompt.contains("Drop noise"))
        #expect(prompt.contains("Consolidate duplicate operational facts"))
        #expect(prompt.contains("Every emitted operational fact must cite at least one capture_event_id"))
        #expect(prompt.contains("provenance_object_id or span_id"))
        #expect(!prompt.contains("Do not create L3 knowledge records"))
        #expect(prompt.contains("Do not promote ordinary operational facts into L3"))
    }

    @Test func l1PromptDefinesUnifiedProjectionIntoL2L3AndL4() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L1 unified projection"))
        #expect(prompt.contains("L2 operational facts"))
        #expect(prompt.contains("L3 reusable knowledge candidates"))
        #expect(prompt.contains("L4 stable entities"))
        #expect(prompt.contains("MemoryOSL1UnifiedProjectionOutput"))
        #expect(prompt.contains("must search existing L2 operational memory"))
        #expect(prompt.contains("must search existing L3/L4"))
        #expect(prompt.contains("record search/judgment evidence"))
    }

    @Test func l1PromptIncludesPromotionFiltersAndStableL4EntityRules() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("signal_quality"))
        #expect(prompt.contains("reuse_scope"))
        #expect(prompt.contains("novelty"))
        #expect(prompt.contains("structurability"))
        #expect(prompt.contains("Stable L4 entity rules"))
        #expect(prompt.contains("Do not create L4 entities for vague temporary phrases"))
    }

    @Test func l2KnowledgePromptDefinesConservativeFourFilterReview() {
        let statement = MemoryOSStatement(id: "stmt-1", subjectID: "node-1", predicate: "prefers", text: "User prefers conservative L3 promotion.", confidence: 0.97, evidenceSpanIDs: ["span-1"])

        let prompt = MemoryOSL2ToKnowledgePromptBuilder().prompt(for: [statement])

        #expect(prompt.contains("Most L2 facts should not become L3 knowledge"))
        #expect(prompt.contains("High confidence alone is insufficient"))
        #expect(prompt.contains("All four filters must pass"))
        #expect(prompt.contains("signal_quality"))
        #expect(prompt.contains("reuse_scope"))
        #expect(prompt.contains("novelty"))
        #expect(prompt.contains("structurability"))
        #expect(prompt.contains("If any dimension fails, do not create L3"))
        #expect(prompt.contains("If existing L3 already covers the idea, output no new L3 candidate"))
        #expect(prompt.contains("If existing L4 already contains the concept, reuse it rather than creating a duplicate"))
        #expect(prompt.contains("must search L2, L3 and L4"))
        #expect(prompt.contains("record the search-backed judgment"))
    }

    @Test func l1PromptDeclaresAllAllowedL2PredicatesAndAssertionKinds() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Allowed L2 assertion_kind values"))
        #expect(prompt.contains("observed"))
        #expect(prompt.contains("inferred"))
        #expect(prompt.contains("summarized"))
        #expect(prompt.contains("Allowed L2 predicates / GraphPredicate raw values"))
        for predicate in GraphPredicate.allCases {
            #expect(prompt.contains(predicate.rawValue))
        }
    }

    @Test func l1PromptDeclaresL2BusinessFactTaxonomyAndMetadataRequirement() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1ToL2PromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L2 fact taxonomy"))
        #expect(prompt.contains("profile_preference"))
        #expect(prompt.contains("project_state"))
        #expect(prompt.contains("task_commitment"))
        #expect(prompt.contains("calendar_time"))
        #expect(prompt.contains("communication"))
        #expect(prompt.contains("source_document"))
        #expect(prompt.contains("decision"))
        #expect(prompt.contains("implementation"))
        #expect(prompt.contains("environment_config"))
        #expect(prompt.contains("relationship"))
        #expect(prompt.contains("other"))
        #expect(prompt.contains("metadata.l2_fact_type"))
        #expect(prompt.contains("metadata.capture_event_ids"))
        #expect(prompt.contains("metadata.provenance_object_ids"))
        #expect(prompt.contains("metadata.span_ids"))
    }
}
