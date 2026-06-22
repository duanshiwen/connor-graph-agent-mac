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
        #expect(prompt.contains("successful L1→L2 projection"))
    }
}
