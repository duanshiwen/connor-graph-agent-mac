import Testing
@testable import ConnorGraphAgentMac

@MainActor
private final class LifecycleTestGate {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Test func appLifecycleStartsInExistingOrderOnlyOnce() async {
    var events: [String] = []
    let lifecycle = AppLifecycle(
        startTaskScheduler: { events.append("scheduler") },
        recoverNoteImports: { events.append("notes") },
        restoreIdentitySession: { events.append("identity") },
        shutdownRuntimeResources: { events.append("shutdown") }
    )

    await lifecycle.startIfNeeded()
    await lifecycle.startIfNeeded()

    #expect(events == ["scheduler", "notes", "identity"])
    #expect(lifecycle.hasStarted)
    #expect(lifecycle.hasFinishedStarting)
    #expect(!lifecycle.isShutdown)
}

@MainActor
@Test func appLifecycleCoalescesConcurrentStartCalls() async {
    var events: [String] = []
    let lifecycle = AppLifecycle(
        startTaskScheduler: { events.append("scheduler") },
        recoverNoteImports: {
            events.append("notes")
            await Task.yield()
        },
        restoreIdentitySession: { events.append("identity") },
        shutdownRuntimeResources: { events.append("shutdown") }
    )

    async let first: Void = lifecycle.startIfNeeded()
    async let second: Void = lifecycle.startIfNeeded()
    _ = await (first, second)

    #expect(events == ["scheduler", "notes", "identity"])
}

@MainActor
@Test func appLifecycleShutdownIsIdempotentAndStopsRemainingStartupStages() async {
    var events: [String] = []
    let gate = LifecycleTestGate()
    let lifecycle = AppLifecycle(
        startTaskScheduler: { events.append("scheduler") },
        recoverNoteImports: {
            events.append("notes")
            await gate.wait()
        },
        restoreIdentitySession: { events.append("identity") },
        shutdownRuntimeResources: { events.append("shutdown") }
    )

    let startup = Task { @MainActor in await lifecycle.startIfNeeded() }
    while !gate.isWaiting {
        await Task.yield()
    }
    lifecycle.shutdown()
    lifecycle.shutdown()
    gate.release()
    await startup.value
    await lifecycle.startIfNeeded()

    #expect(events == ["scheduler", "notes", "shutdown"])
    #expect(lifecycle.isShutdown)
    #expect(!lifecycle.hasFinishedStarting)
}
