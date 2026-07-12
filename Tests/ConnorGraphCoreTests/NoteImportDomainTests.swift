import Foundation
import Testing
@testable import ConnorGraphCore

@Suite("Note import domain")
struct NoteImportDomainTests {
    @Test("LLM concurrency is bounded for commercial background execution")
    func boundsLLMConcurrency() {
        #expect(NoteImportOptions(llmConcurrency: 0).llmConcurrency == 1)
        #expect(NoteImportOptions(llmConcurrency: 2).llmConcurrency == 2)
        #expect(NoteImportOptions(llmConcurrency: 100).llmConcurrency == 3)
    }

    @Test("Job follows review, import, processing, and completion lifecycle")
    func validatesJobLifecycle() throws {
        let machine = NoteImportStateMachine()
        try machine.validate(jobFrom: .created, to: .scanning)
        try machine.validate(jobFrom: .scanning, to: .awaitingReview)
        try machine.validate(jobFrom: .awaitingReview, to: .ready)
        try machine.validate(jobFrom: .ready, to: .importing)
        try machine.validate(jobFrom: .importing, to: .processing)
        try machine.validate(jobFrom: .processing, to: .completed)
        #expect(NoteImportJobStatus.completed.isTerminal)
    }

    @Test("Paused jobs resume only into an active persisted phase")
    func validatesPauseAndResume() throws {
        let machine = NoteImportStateMachine()
        try machine.validate(jobFrom: .importing, to: .paused)
        try machine.validate(jobFrom: .paused, to: .importing)
        try machine.validate(jobFrom: .processing, to: .paused)
        try machine.validate(jobFrom: .paused, to: .processing)
    }

    @Test("Invalid job transition is rejected")
    func rejectsInvalidJobTransition() {
        let machine = NoteImportStateMachine()
        #expect(throws: NoteImportStateTransitionError.invalidJobTransition(from: .created, to: .completed)) {
            try machine.validate(jobFrom: .created, to: .completed)
        }
    }

    @Test("Imported item may complete without LLM or enter the LLM queue")
    func supportsOptionalLLMProcessing() throws {
        let machine = NoteImportStateMachine()
        try machine.validate(itemFrom: .imported, to: .completed)
        try machine.validate(itemFrom: .imported, to: .queuedForLLM)
        try machine.validate(itemFrom: .queuedForLLM, to: .runningLLM)
        try machine.validate(itemFrom: .runningLLM, to: .completed)
    }

    @Test("Low confidence decoding requires review before session creation")
    func requiresEncodingReview() throws {
        let machine = NoteImportStateMachine()
        try machine.validate(itemFrom: .validating, to: .needsEncodingReview)
        try machine.validate(itemFrom: .needsEncodingReview, to: .ready)
        #expect(throws: NoteImportStateTransitionError.invalidItemTransition(from: .needsEncodingReview, to: .creatingSession)) {
            try machine.validate(itemFrom: .needsEncodingReview, to: .creatingSession)
        }
    }

    @Test("A failed LLM run can be retried without recreating its session")
    func retriesLLMFailure() throws {
        let machine = NoteImportStateMachine()
        try machine.validate(itemFrom: .runningLLM, to: .llmFailed)
        try machine.validate(itemFrom: .llmFailed, to: .queuedForLLM)
        #expect(NoteImportItemStatus.llmFailed.isTerminal)
    }

    @Test("Imported note round trips source provenance")
    func importedNoteCodableRoundTrip() throws {
        let note = ImportedNote(
            sourceKind: .obsidianVault,
            sourceIdentity: "vault-1:projects/connor.md",
            externalID: nil,
            sourcePath: "/vault/projects/connor.md",
            relativePath: "projects/connor.md",
            title: "Connor",
            markdownContent: "# Connor\n",
            tags: ["agent-os"],
            hierarchy: ["projects"],
            rawByteHash: "raw",
            normalizedTextHash: "text"
        )

        let encoded = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(ImportedNote.self, from: encoded)
        #expect(decoded == note)
    }
}
