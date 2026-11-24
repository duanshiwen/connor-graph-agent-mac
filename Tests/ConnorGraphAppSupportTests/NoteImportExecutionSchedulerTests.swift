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

    @Test("Paused imports resume without dropping or reordering work")
    func pauseAndResume() async throws {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 1))
        let (started, continuation) = AsyncStream<Int>.makeStream()
        let task = Task {
            await scheduler.run(elements: [0, 1, 2]) { value in
                if value == 0 { await scheduler.pause() }
                continuation.yield(value)
                return value
            }
        }
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() == 0)
        try await Task.sleep(for: .milliseconds(30))
        await scheduler.resume()
        let results = await task.value
        #expect(results.compactMap { try? $0.get() } == [0, 1, 2])
        continuation.finish()
    }

    @Test("Cancelling a paused scheduler wakes it and preserves completed work")
    func cancelWhilePaused() async {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 1))
        let (started, continuation) = AsyncStream<Int>.makeStream()
        let task = Task {
            await scheduler.run(elements: [0, 1, 2]) { value in
                await scheduler.pause()
                continuation.yield(value)
                return value
            }
        }
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() == 0)
        await scheduler.cancel()
        #expect(await task.value.compactMap { try? $0.get() } == [0])
        continuation.finish()
    }

    @Test("Parent cancellation exits a paused import without a busy loop")
    func parentCancellationWhilePaused() async throws {
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 1))
        let (started, continuation) = AsyncStream<Int>.makeStream()
        let task = Task {
            await scheduler.run(elements: [0, 1, 2]) { value in
                await scheduler.pause()
                continuation.yield(value)
                return value
            }
        }
        var iterator = started.makeAsyncIterator()
        #expect(await iterator.next() == 0)
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let (finished, completed) = AsyncStream<Bool>.makeStream()
        let observer = Task { _ = await task.value; completed.yield(true) }
        // Rescue the old polling implementation so a regression fails without
        // leaving an uncancellable spinning task in the test process.
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            completed.yield(false)
            await scheduler.cancel()
        }
        var completion = finished.makeAsyncIterator()
        #expect(await completion.next() == true)
        watchdog.cancel()
        await observer.value
        #expect(await task.value.compactMap { try? $0.get() } == [0])
        continuation.finish()
        completed.finish()
    }

}
