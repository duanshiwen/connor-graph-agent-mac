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
        #expect(presentation.helpText == "打开导入中心 · 2 个导入任务 · 50%")
        #expect(presentation.accessibilityValue == "2 个任务，正在进行，进度 50%")
    }

    @Test("Describes indeterminate scanning")
    func scanning() {
        let presentation = presentation(for: [job(status: .scanning)])
        #expect(presentation.helpText == "打开导入中心 · 正在扫描导入内容")
        #expect(presentation.accessibilityValue == "1 个任务，正在进行，进度未知")
    }

    @Test("Describes paused progress")
    func paused() {
        let presentation = presentation(for: [job(status: .paused, discovered: 4, imported: 1)])
        #expect(presentation.helpText == "打开导入中心 · 1 个导入任务已暂停 · 25%")
        #expect(presentation.accessibilityValue == "1 个任务，已暂停，进度 25%")
    }

    @Test("Describes cancellation")
    func cancelling() {
        let presentation = presentation(for: [job(status: .cancelling, discovered: 4, imported: 1)])
        #expect(presentation.helpText == "打开导入中心 · 1 个导入任务正在取消 · 25%")
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
