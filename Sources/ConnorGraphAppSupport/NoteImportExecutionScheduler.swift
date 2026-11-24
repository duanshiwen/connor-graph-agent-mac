import Foundation

public actor NoteImportExecutionScheduler {
    public struct Configuration: Sendable, Equatable {
        public var concurrency: Int
        public var leaseDuration: TimeInterval
        public var pageSize: Int
        public init(concurrency: Int = 1, leaseDuration: TimeInterval = 120, pageSize: Int = 32) {
            self.concurrency = min(max(concurrency, 1), 3); self.leaseDuration = max(leaseDuration, 1); self.pageSize = max(pageSize, 1)
        }
    }

    private var configuration: Configuration
    private var pauseRequested = false
    private var cancelRequested = false
    private var activeCount = 0
    private var peakActiveCount = 0
    private var pauseWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public init(configuration: Configuration = .init()) { self.configuration = configuration }
    public func update(configuration: Configuration) { self.configuration = configuration }
    public func pause() { pauseRequested = true }
    public func resume() { pauseRequested = false; releasePauseWaiters() }
    public func cancel() { cancelRequested = true; pauseRequested = false; releasePauseWaiters() }
    public func resetCancellation() { cancelRequested = false }
    public func peakConcurrency() -> Int { peakActiveCount }

    private func releasePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        for waiter in waiters.values { waiter.resume() }
    }

    private func releasePauseWaiter(_ id: UUID) {
        pauseWaiters.removeValue(forKey: id)?.resume()
    }

    private func waitWhilePaused() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if !pauseRequested || cancelRequested || Task.isCancelled {
                    continuation.resume()
                } else {
                    pauseWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.releasePauseWaiter(id) }
        }
    }

    public func run<Element: Sendable, Result: Sendable>(
        elements: [Element],
        operation: @escaping @Sendable (Element) async throws -> Result
    ) async -> [Swift.Result<Result, Error>] {
        guard !elements.isEmpty, !Task.isCancelled else { return [] }
        let limit = configuration.concurrency
        return await withTaskGroup(of: (Int, Swift.Result<Result, Error>).self, returning: [Swift.Result<Result, Error>].self) { group in
            var next = 0
            var results = Array<Swift.Result<Result, Error>?>(repeating: nil, count: elements.count)
            func submit(_ index: Int) {
                let element = elements[index]
                group.addTask(priority: .utility) {
                    do { return (index, .success(try await operation(element))) }
                    catch { return (index, .failure(error)) }
                }
            }
            while next < min(limit, elements.count) { submit(next); next += 1; activeCount += 1; peakActiveCount = max(peakActiveCount, activeCount) }
            while let (index, result) = await group.next() {
                activeCount -= 1; results[index] = result
                while pauseRequested && !cancelRequested && !Task.isCancelled { await waitWhilePaused() }
                if !cancelRequested, !Task.isCancelled, next < elements.count {
                    await Task.yield()
                    guard !Task.isCancelled else { group.cancelAll(); continue }
                    submit(next); next += 1; activeCount += 1; peakActiveCount = max(peakActiveCount, activeCount)
                }
            }
            return results.compactMap { $0 }
        }
    }
}
