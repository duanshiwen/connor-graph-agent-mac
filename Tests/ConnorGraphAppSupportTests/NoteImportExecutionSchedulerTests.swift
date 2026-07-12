import Foundation
import Testing
@testable import ConnorGraphAppSupport

private actor ConcurrencyProbe {
    var active = 0; var peak = 0
    func begin() { active += 1; peak = max(peak, active) }
    func end() { active -= 1 }
}

@Suite("Note import execution scheduler")
struct NoteImportExecutionSchedulerTests {
    @Test("Bounds execution concurrency to configured commercial range")
    func boundsConcurrency() async {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 9))
        let probe = ConcurrencyProbe()
        let results = await scheduler.run(elements: Array(0..<12)) { value in await probe.begin(); try await Task.sleep(for: .milliseconds(15)); await probe.end(); return value }
        #expect(results.count == 12); #expect(await probe.peak == 3); #expect(await scheduler.peakConcurrency() == 3)
    }

    @Test("Cancellation prevents undispatched work")
    func cancelsRemaining() async {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 1))
        let task = Task { await scheduler.run(elements: Array(0..<10)) { value in try await Task.sleep(for: .milliseconds(20)); return value } }
        try? await Task.sleep(for: .milliseconds(5)); await scheduler.cancel()
        let results = await task.value
        #expect(results.count == 1)
    }
}
