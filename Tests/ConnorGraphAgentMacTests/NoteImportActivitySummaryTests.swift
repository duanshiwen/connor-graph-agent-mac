import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Note import activity summary")
struct NoteImportActivitySummaryTests {
    @Test("Shows every nonterminal status", arguments: [
        NoteImportJobStatus.created,
        .scanning,
        .awaitingReview,
        .ready,
        .importing,
        .processing,
        .paused,
        .cancelling
    ])
    func showsNonterminalStatus(_ status: NoteImportJobStatus) {
        let summary = NoteImportActivitySummary(jobs: [job(status: status)])
        #expect(summary.isVisible)
        #expect(summary.visibleJobCount == 1)
    }

    @Test("Hides every terminal status", arguments: [
        NoteImportJobStatus.cancelled,
        .completedWithIssues,
        .completed,
        .failed
    ])
    func hidesTerminalStatus(_ status: NoteImportJobStatus) {
        let summary = NoteImportActivitySummary(jobs: [job(status: status)])
        #expect(!summary.isVisible)
        #expect(summary.visibleJobCount == 0)
    }

    @Test("Aggregates progress by item count and includes duplicates and failures")
    func aggregatesWeightedProgress() {
        let summary = NoteImportActivitySummary(jobs: [
            job(status: .importing, discovered: 10, imported: 3, duplicates: 2, failed: 1),
            job(status: .processing, discovered: 2, imported: 1),
            job(status: .completed, discovered: 100, imported: 100)
        ])

        #expect(summary.visibleJobCount == 2)
        #expect(summary.processedCount == 7)
        #expect(summary.totalCount == 12)
        #expect(summary.progressFraction == 7.0 / 12.0)
    }

    @Test("Clamps processed progress to each job total")
    func clampsProcessedProgress() {
        let summary = NoteImportActivitySummary(jobs: [
            job(status: .processing, discovered: 2, imported: 2, duplicates: 3, failed: 4)
        ])
        #expect(summary.processedCount == 2)
        #expect(summary.progressFraction == 1)
    }

    @Test("Uses indeterminate progress while all totals are unknown")
    func unknownProgress() {
        let summary = NoteImportActivitySummary(jobs: [job(status: .scanning)])
        #expect(summary.progressFraction == nil)
        #expect(summary.hasUnknownProgress)
        #expect(summary.scanningJobCount == 1)
    }

    @Test("Keeps known aggregate while marking an additional unknown task")
    func mixedKnownAndUnknownProgress() {
        let summary = NoteImportActivitySummary(jobs: [
            job(status: .importing, discovered: 4, imported: 2),
            job(status: .scanning)
        ])
        #expect(summary.progressFraction == 0.5)
        #expect(summary.hasUnknownProgress)
    }

    @Test("Treats a requested pause as paused before status transition")
    func requestedPause() {
        var pausing = job(status: .processing, discovered: 4, imported: 1)
        pausing.pauseRequestedAt = Date()
        let summary = NoteImportActivitySummary(jobs: [pausing])
        #expect(summary.pausedJobCount == 1)
        #expect(summary.runningJobCount == 0)
        #expect(summary.presentationState == .paused)
    }

    @Test("Prioritizes cancellation presentation")
    func cancellingPresentation() {
        let summary = NoteImportActivitySummary(jobs: [
            job(status: .paused, discovered: 4, imported: 1),
            job(status: .cancelling, discovered: 2, imported: 1)
        ])
        #expect(summary.presentationState == .cancelling)
    }

    private func job(
        status: NoteImportJobStatus,
        discovered: Int = 0,
        imported: Int = 0,
        duplicates: Int = 0,
        failed: Int = 0
    ) -> NoteImportJobRecord {
        NoteImportJobRecord(
            sourceID: UUID().uuidString,
            status: status,
            discoveredCount: discovered,
            importedCount: imported,
            duplicateCount: duplicates,
            failedCount: failed
        )
    }
}
