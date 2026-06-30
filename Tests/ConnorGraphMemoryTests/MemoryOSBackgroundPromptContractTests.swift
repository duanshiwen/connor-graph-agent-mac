import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Suite("Memory OS Background Prompt Contract Tests")
struct MemoryOSBackgroundPromptContractTests {
    @Test func l1UnifiedProjectionPromptRendersCaptureEventsAsJSONArray() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let events = [
            MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: now, tokenEstimate: 42, metadata: ["span_id": "span-1", "source_kind": "mail", "title": "Mail A", "content_preview": "User wants L1 cleared after successful processing."]),
            MemoryOSCaptureEvent(id: "cap-2", provenanceObjectID: "prov-2", eventType: "source_event", occurredAt: now.addingTimeInterval(60), tokenEstimate: 84, metadata: ["span_id": "span-2", "source_kind": "rss", "title": "RSS B", "content_preview": "Memory OS should preserve L0 as durable evidence."])
        ]

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: events)

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

    @Test func l1PromptStatesL1IsCacheBufferAndL0IsDurableEvidence() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Immutable provenance vault"))
        #expect(prompt.contains("Cache buffer"))
        #expect(prompt.contains("processed L1 events are cleared"))
        #expect(prompt.contains("L0 retains the original evidence"))
    }

    @Test func l1PromptDefinesDisciplinedFactExtractionWorkflow() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Read L1 events in chronological order"))
        #expect(prompt.contains("extract candidate operational facts"))
        #expect(prompt.contains("Drop noise"))
        #expect(prompt.contains("Consolidate duplicate operational facts"))
        #expect(prompt.contains("Do not promote ordinary operational facts into L3"))
    }

    @Test func l1PromptDefinesDirectWriteToL2L3AndL4() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("directly write to L2, L3, and L4"))
        #expect(prompt.contains("L2 entity-centered working memory"))
        #expect(prompt.contains("L3 reusable knowledge candidates"))
        #expect(prompt.contains("L4 stable entities"))
        #expect(prompt.contains("memory_os_l2_update_entities"))
        #expect(prompt.contains("memory_os_l3_update_beliefs"))
        #expect(prompt.contains("memory_os_l4_update_entities"))
        #expect(prompt.contains("memory_os_update_current_user_profile"))
        #expect(prompt.contains("Do not output JSON artifacts"))
    }

    @Test func l1PromptTeachesL2NegativeDecisionPreservation() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Preserve negative or exclusion semantics"))
    }

    @Test func l1PromptIncludesPromotionFiltersAndStableL4EntityRules() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("signal_quality"))
        #expect(prompt.contains("reuse_scope"))
        #expect(prompt.contains("novelty"))
        #expect(prompt.contains("structurability"))
        #expect(prompt.contains("Stable L4 entity rules"))
        #expect(prompt.contains("Do not create L4 entities for vague temporary phrases"))
    }

    @Test func l1PromptDefinesSimplifiedL3DisciplineDomainAndRelatedConceptRules() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Domain means discipline classification"))
        #expect(prompt.contains("relatedEntityNames is a comma-separated list of durable L4 concept entity names"))
        #expect(prompt.contains("must not contain project names, product names, module names, file names, people names"))
    }

    @Test func l1PromptDefinesL2SemanticAnchorsBeyondPhysicalObjects() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("A L2 entity is any future-useful semantic anchor"))
        #expect(prompt.contains("not only a physical object"))
        #expect(prompt.contains("person_object"))
        #expect(prompt.contains("work_object"))
        #expect(prompt.contains("life_object"))
        #expect(prompt.contains("event"))
        #expect(prompt.contains("place"))
        #expect(prompt.contains("artifact"))
        #expect(prompt.contains("document"))
        #expect(prompt.contains("concept"))
        #expect(prompt.contains("metric"))
        #expect(prompt.contains("time_expression"))
        #expect(prompt.contains("task topic"))
        #expect(prompt.contains("decision topic"))
        #expect(prompt.contains("project phase"))
        #expect(prompt.contains("Do not create an entity merely because a noun phrase appears"))
    }

    @Test func l1PromptRequiresFactFirstEntitySecondExtraction() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("fact-first, entity-second"))
        #expect(prompt.contains("first identify future-useful operational facts"))
        #expect(prompt.contains("Classify each retained fact into exactly one factType"))
        #expect(prompt.contains("Choose the minimal useful subject entity anchor"))
        #expect(prompt.contains("Preserve negation, exclusion, rejection, cancellation, postponement, and supersession"))
    }

    @Test func l1PromptDefinesMinimumEntityPrinciple() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Minimum entity principle"))
        #expect(prompt.contains("Create or update the fewest entities needed"))
        #expect(prompt.contains("A good L2 entity is a future retrieval anchor"))
        #expect(prompt.contains("A bad L2 entity is merely a noun phrase"))
        #expect(prompt.contains("Prefer attaching a statement to an existing broader anchor"))
    }

    @Test func l1PromptProvidesClassSpecificExtractionCues() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Class-specific extraction cues"))
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
        #expect(prompt.contains("selected option, explicit decision, rejection, approval, rationale"))
        #expect(prompt.contains("code, architecture, runtime behavior, dependency, module relation, bug, fix, feature, test result"))
        #expect(prompt.contains("branch, toolchain, config, permission mode, workspace path"))
        #expect(prompt.contains("Use only when the fact is future-useful operational memory and no other category fits"))
    }

    @Test func l1PromptDefinesCurrentUserAndOtherPersonBoundary() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("The current user is the human operating this Connor installation"))
        #expect(prompt.contains("memory_os_update_current_user_profile"))
        #expect(prompt.contains("Do not create L2 entities named"))
        #expect(prompt.contains("Do not treat assistant-authored assumptions"))
        #expect(prompt.contains("Other named or described people use memory_os_l2_update_entities"))
    }

    @Test func l1PromptRequiresFactTypeTaxonomy() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L2 fact taxonomy"))
        #expect(prompt.contains("factType"))
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
    }

    @Test func l1PromptDeclaresAllowedL2PredicatesAndL4RelationPredicates() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Allowed L2 predicates / GraphPredicate raw values"))
        for predicate in GraphPredicate.allCases {
            #expect(prompt.contains(predicate.rawValue))
        }
        #expect(prompt.contains("Allowed L4 relation predicates"))
        #expect(prompt.contains("Do not invent predicates"))
        #expect(prompt.contains("Map is_a"))
        #expect(prompt.contains("Map has_a"))
        #expect(prompt.contains("RELATED_TO only as a last resort"))
        for predicate in MemoryOSL4RelationPredicate.allCases {
            #expect(prompt.contains(predicate.rawValue))
        }
    }

    @Test func l1PromptDeclaresPersonFeatureExtractionPolicy() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Person feature extraction policy"))
        #expect(prompt.contains("preference, dislike, habit, goal, stable_trait"))
        #expect(prompt.contains("Current-user profile_preference facts"))
        #expect(prompt.contains("Other-person profile facts"))
        #expect(prompt.contains("Do not infer medical, psychological, or sensitive identity diagnoses"))
    }

    @Test func l1PromptClarifiesPersonProfileFactRouting() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Person/profile routing rules"))
        #expect(prompt.contains("Current-user facts → memory_os_update_current_user_profile"))
        #expect(prompt.contains("Other-person facts → memory_os_l2_update_entities"))
        #expect(prompt.contains("Do not promote ordinary person profile facts into L3"))
    }

    @Test func l1PromptDeclaresToolUsageSummary() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Tool usage summary"))
        #expect(prompt.contains("memory_os_context"))
        #expect(prompt.contains("memory_os_l2_update_entities"))
        #expect(prompt.contains("memory_os_update_current_user_profile"))
        #expect(prompt.contains("memory_os_l3_update_beliefs"))
        #expect(prompt.contains("memory_os_l4_update_entities"))
        #expect(prompt.contains("memory_os_search"))
        #expect(prompt.contains("memory_os_expand_l4"))
    }

    @Test func l1PromptClarifiesCurrentUserDoesNotNeedContextCheck() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Do NOT call memory_os_context first for current-user facts"))
        #expect(prompt.contains("memory_os_update_current_user_profile directly"))
        #expect(prompt.contains("Skip for current-user facts"))
    }

}
