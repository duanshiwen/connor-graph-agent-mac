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

    @Test func l1PromptStatesL1IsActiveBufferAndL0IsDurableEvidence() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L0 is the durable provenance layer"))
        #expect(prompt.contains("L1 is the active processing buffer"))
        #expect(prompt.contains("successful L1 unified projection"))
    }

    @Test func l1PromptDefinesDisciplinedFactExtractionWorkflow() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Read L1 events in chronological order"))
        #expect(prompt.contains("Extract candidate operational facts per event"))
        #expect(prompt.contains("Drop noise"))
        #expect(prompt.contains("Consolidate duplicate operational facts"))
        #expect(prompt.contains("L2 itself does not require evidence spans"))
        #expect(prompt.contains("provenance identifiers only as optional internal metadata"))
        #expect(!prompt.contains("Do not create L3 knowledge records"))
        #expect(prompt.contains("Do not promote ordinary operational facts into L3"))
    }

    @Test func l1PromptDefinesUnifiedProjectionIntoL2L3AndL4() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L1 unified projection"))
        #expect(prompt.contains("L2 entity-centered working memory"))
        #expect(prompt.contains("L3 reusable knowledge candidates"))
        #expect(prompt.contains("L4 stable entities"))
        #expect(prompt.contains("MemoryOSL1UnifiedProjectionOutput"))
        #expect(prompt.contains("memory_os_l2_find_entities"))
        #expect(prompt.contains("memory_os_l2_update_entities"))
        #expect(prompt.contains("must search existing L3/L4"))
        #expect(prompt.contains("record search/judgment rationale"))
    }

    @Test func l1PromptTeachesL2NoEvidenceAndNegativeDecisionPreservation() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("L2 is entity-centered working memory, not an evidence store"))
        #expect(prompt.contains("Do not ask LLM tools to provide evidence"))
        #expect(prompt.contains("statement text is the semantic authority"))
        #expect(prompt.contains("Preserve negative or exclusion semantics"))
        #expect(prompt.contains("statement text is the semantic authority"))
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
        #expect(prompt.contains("memory_os_l3_list_domains"))
        #expect(prompt.contains("related_object_names is a comma-separated list of durable L4 concept entity names or aliases"))
        #expect(prompt.contains("must not contain project names, product names, module names, file names, people names"))
        #expect(prompt.contains("claim as statement, discipline domain, related L4 concept names/aliases"))
    }

    @Test func l1PromptDefinesL2SemanticAnchorsBeyondPhysicalObjects() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("A L2 entity is any future-useful semantic anchor"))
        #expect(prompt.contains("not only a physical object"))
        #expect(prompt.contains("current_user"))
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
        #expect(prompt.contains("Classify each retained fact into exactly one metadata.l2_fact_type before creating entities"))
        #expect(prompt.contains("Choose the minimal useful subject entity anchor"))
        #expect(prompt.contains("statement text is the semantic authority"))
        #expect(prompt.contains("Predicate/relation is a routing and retrieval handle"))
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
        #expect(prompt.contains("branch, toolchain, credential boundary, config, permission mode, workspace path"))
        #expect(prompt.contains("Use only when the fact is future-useful operational memory and no other category fits"))
    }

    @Test func l1PromptProvidesStatementWritingTemplates() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Statement writing templates"))
        #expect(prompt.contains("Preference:"))
        #expect(prompt.contains("Project state:"))
        #expect(prompt.contains("Decision:"))
        #expect(prompt.contains("Task:"))
        #expect(prompt.contains("Implementation:"))
        #expect(prompt.contains("Source document:"))
        #expect(prompt.contains("Relationship:"))
        #expect(prompt.contains("Avoid vague statements"))
    }

    @Test func l1PromptDefinesProtectedCurrentUserPersonObjectAnchor() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("semantically a person_object"))
        #expect(prompt.contains("protected identity anchor"))
        #expect(prompt.contains("Do not create separate entities named"))
        #expect(prompt.contains("Do not add generic aliases"))
        #expect(prompt.contains("assistant-authored assumptions"))
        #expect(prompt.contains("unless the user explicitly confirms them"))
    }

    @Test func l1PromptDocumentsMinimalCurrentUserFactWriteToolContract() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("memory_os_update_current_user_profile"))
        #expect(prompt.contains("facts[].statement"))
        #expect(prompt.contains("facts[].factType"))
        #expect(prompt.contains("facts[].relation"))
        #expect(prompt.contains("Do not provide evidence, confidence, metadata, validAt, profileDimension, source, stability, sensitivity, observations, or mode"))
        #expect(prompt.contains("The tool owns current_user anchoring, metadata construction, timestamps, confidence defaults, and projection details"))
    }

    @Test func l1PromptSeparatesArtifactMetadataFromExternalToolArguments() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Inside MemoryOSL1UnifiedProjectionOutput"))
        #expect(prompt.contains("metadata.profile_dimension is an internal validation/routing key"))
        #expect(prompt.contains("If no specific profile dimension is available, use fact_statement"))
        #expect(prompt.contains("This metadata requirement is for this L1 artifact only"))
        #expect(prompt.contains("Do not ask external write tools to provide metadata"))
    }

    @Test func l1PromptDeclaresAllAllowedL2PredicatesAndAssertionKinds() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Allowed L2 assertion_kind values"))
        #expect(prompt.contains("observed"))
        #expect(prompt.contains("inferred"))
        #expect(prompt.contains("summarized"))
        #expect(prompt.contains("Allowed L2 predicates / GraphPredicate raw values"))
        for predicate in GraphPredicate.allCases {
            #expect(prompt.contains(predicate.rawValue))
        }
    }

    @Test func l1PromptDeclaresAllowedL4RelationPredicatesAndMappingRules() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Allowed L4 relation predicates"))
        #expect(prompt.contains("Do not invent predicates"))
        #expect(prompt.contains("Map is_a"))
        #expect(prompt.contains("Map has_a"))
        #expect(prompt.contains("RELATED_TO only as a last resort"))
        for predicate in MemoryOSL4RelationPredicate.allCases {
            #expect(prompt.contains(predicate.rawValue))
        }
    }

    @Test func l1PromptDeclaresL2BusinessFactTaxonomyAndMetadataRequirement() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

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

    @Test func l1PromptDefinesCurrentUserAndOtherPersonBoundary() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("The current user is the human operating this Connor installation/session"))
        #expect(prompt.contains("Other named or described people are other_person entities"))
        #expect(prompt.contains("Do not merge other people into the current user"))
        #expect(prompt.contains("Do not assign another person's preferences"))
    }

    @Test func l1PromptRequiresPersonRoleMetadataForProfileFacts() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("metadata.person_role"))
        #expect(prompt.contains("current_user"))
        #expect(prompt.contains("other_person"))
        #expect(prompt.contains("ambiguous_person"))
        #expect(prompt.contains("metadata.person_resolution"))
    }

    @Test func l1PromptClarifiesPersonProfileFactRouting() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Current-user preferences, habits, goals, stable traits, constraints, emotional-support preferences, communication preferences, interaction guidance and knowledge background are L2 profile_preference facts"))
        #expect(prompt.contains("Other-person profile facts may also be L2 profile_preference or relationship facts"))
        #expect(prompt.contains("Ambiguous people must be marked ambiguous_person / needs_confirmation"))
        #expect(prompt.contains("Do not promote ordinary person profile facts into L3 merely because confidence is high"))
    }

    @Test func l1PromptRequiresMaturePersonFeatureMetadataAndIdentitySignals() {
        let event = MemoryOSCaptureEvent(id: "cap-1", provenanceObjectID: "prov-1", eventType: "source_event", occurredAt: Date(timeIntervalSince1970: 1_780_000_000), metadata: ["span_id": "span-1"])

        let prompt = MemoryOSL1UnifiedProjectionPromptBuilder().prompt(for: [event])

        #expect(prompt.contains("Person feature extraction policy"))
        #expect(prompt.contains("metadata.profile_dimension"))
        #expect(prompt.contains("metadata.evidence_quality"))
        #expect(prompt.contains("metadata.stability"))
        #expect(prompt.contains("metadata.identity_anchor = current_user"))
        #expect(prompt.contains("contact_id"))
        #expect(prompt.contains("normalized_email"))
        #expect(prompt.contains("mail senders/recipients"))
        #expect(prompt.contains("calendar attendees/organizers"))
        #expect(prompt.contains("Do not treat generic words such as user, users, 用户, 当前用户, profile"))
        #expect(prompt.contains("Do not infer medical, psychological, or sensitive identity diagnoses"))
    }

}

