import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Note import toolbar presentation")
struct NoteImportToolbarPresentationTests {
    @Test("Describes determinate running progress")
    func runningProgress() {
        let presentation = presentation(for: [
            job(status: .processing, discovered: 4, imported: 1),
            job(status: .importing, discovered: 4, imported: 3)
        ])
        #expect(presentation.helpText == "打开笔记导入中心 · 2 个导入任务 · 50%")
        #expect(presentation.accessibilityValue == "2 个任务，正在进行，进度 50%")
    }

    @Test("Describes indeterminate scanning")
    func scanning() {
        let presentation = presentation(for: [job(status: .scanning)])
        #expect(presentation.helpText == "打开笔记导入中心 · 正在扫描导入内容")
        #expect(presentation.accessibilityValue == "1 个任务，正在进行，进度未知")
    }

    @Test("Describes paused progress")
    func paused() {
        let presentation = presentation(for: [job(status: .paused, discovered: 4, imported: 1)])
        #expect(presentation.helpText == "打开笔记导入中心 · 1 个导入任务已暂停 · 25%")
        #expect(presentation.accessibilityValue == "1 个任务，已暂停，进度 25%")
    }

    @Test("Uses one pause or resume control for the current job state")
    func singlePauseResumeControl() throws {
        let running = try #require(NoteImportControlPresentation(job: job(status: .processing)))
        #expect(running.action == .pause)
        #expect(running.title == "暂停")
        #expect(running.systemImage == "pause")

        var requestedPause = job(status: .processing)
        requestedPause.pauseRequestedAt = Date()
        let paused = try #require(NoteImportControlPresentation(job: requestedPause))
        #expect(paused.action == .resume)
        #expect(paused.title == "继续")
        #expect(paused.systemImage == "play")

        let legacyPaused = try #require(NoteImportControlPresentation(job: job(status: .paused)))
        #expect(legacyPaused.action == .resume)
        #expect(NoteImportControlPresentation(job: job(status: .awaitingReview)) == nil)
        #expect(NoteImportControlPresentation(job: job(status: .completed)) == nil)
    }

    @Test("Requested pause drives the visible job status")
    func requestedPauseStatus() {
        var job = job(status: .processing)
        job.pauseRequestedAt = Date()
        let presentation = NoteImportJobPresentation(job: job)
        #expect(presentation.displayName == "已暂停")
        #expect(presentation.systemImage == "pause.circle.fill")
    }

    @Test("Cancel request overrides a stale processing presentation")
    func requestedCancellationOverridesProcessing() {
        var requestedCancellation = job(status: .processing)
        requestedCancellation.cancelRequestedAt = Date()
        let jobPresentation = NoteImportJobPresentation(job: requestedCancellation, runtimeState: nil)
        #expect(jobPresentation.displayName == "正在取消")
        #expect(NoteImportControlPresentation(job: requestedCancellation, runtimeState: nil) == nil)
        let toolbar = presentation(for: [requestedCancellation])
        #expect(toolbar.accessibilityValue.contains("正在取消"))
    }

    @Test("Terminal cancellation wins over its persisted request timestamp")
    func terminalCancellationWinsOverRequestTimestamp() {
        var cancelled = job(status: .cancelled, discovered: 392, imported: 253)
        cancelled.cancelRequestedAt = Date()

        let presentation = NoteImportJobPresentation(job: cancelled, runtimeState: nil)

        #expect(presentation.displayName == "已取消")
        #expect(presentation.systemImage == "xmark.circle")
        #expect(NoteImportControlPresentation(job: cancelled, runtimeState: nil) == nil)
    }

    @Test("Missing runner offers one explicit recovery action")
    func missingRunnerOffersRecovery() throws {
        let interrupted = job(status: .processing)
        let jobPresentation = NoteImportJobPresentation(job: interrupted, runtimeState: nil)
        #expect(jobPresentation.displayName == "导入已中断")
        let control = try #require(NoteImportControlPresentation(job: interrupted, runtimeState: nil))
        #expect(control.action == .restart)
        #expect(control.title == "继续剩余任务")
        #expect(control.systemImage == "arrow.clockwise")
    }

    @Test("Orphaned post-scan job offers recovery instead of waiting forever")
    func orphanedAwaitingReviewOffersRecovery() throws {
        let orphaned = job(status: .awaitingReview)
        let presentation = NoteImportJobPresentation(job: orphaned, runtimeState: nil)
        let control = try #require(NoteImportControlPresentation(job: orphaned, runtimeState: nil))

        #expect(presentation.displayName == "导入已中断")
        #expect(control.action == .restart)
        #expect(control.title == "继续剩余任务")
    }

    @Test("Describes cancellation")
    func cancelling() {
        let presentation = presentation(for: [job(status: .cancelling, discovered: 4, imported: 1)])
        #expect(presentation.helpText == "打开笔记导入中心 · 1 个导入任务正在取消 · 25%")
        #expect(presentation.accessibilityValue == "1 个任务，正在取消，进度 25%")
    }

    private func presentation(for jobs: [NoteImportJobRecord]) -> NoteImportToolbarPresentation {
        NoteImportToolbarPresentation(summary: NoteImportActivitySummary(jobs: jobs))
    }

    private func job(
        status: NoteImportJobStatus,
        discovered: Int = 0,
        imported: Int = 0
    ) -> NoteImportJobRecord {
        NoteImportJobRecord(
            sourceID: UUID().uuidString,
            status: status,
            discoveredCount: discovered,
            importedCount: imported
        )
    }
}
