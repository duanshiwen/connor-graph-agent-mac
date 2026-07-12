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

    public init(configuration: Configuration = .init()) { self.configuration = configuration }
    public func update(configuration: Configuration) { self.configuration = configuration }
    public func pause() { pauseRequested = true }
    public func resume() { pauseRequested = false }
    public func cancel() { cancelRequested = true; pauseRequested = false }
    public func resetCancellation() { cancelRequested = false }
    public func peakConcurrency() -> Int { peakActiveCount }

    public func run<Element: Sendable, Result: Sendable>(
        elements: [Element],
        operation: @escaping @Sendable (Element) async throws -> Result
    ) async -> [Swift.Result<Result, Error>] {
        guard !elements.isEmpty else { return [] }
        let limit = configuration.concurrency
        return await withTaskGroup(of: (Int, Swift.Result<Result, Error>).self, returning: [Swift.Result<Result, Error>].self) { group in
            var next = 0
            var results = Array<Swift.Result<Result, Error>?>(repeating: nil, count: elements.count)
            func submit(_ index: Int) {
                let element = elements[index]
                group.addTask { do { return (index, .success(try await operation(element))) } catch { return (index, .failure(error)) } }
            }
            while next < min(limit, elements.count) { submit(next); next += 1; activeCount += 1; peakActiveCount = max(peakActiveCount, activeCount) }
            while let (index, result) = await group.next() {
                activeCount -= 1; results[index] = result
                while pauseRequested && !cancelRequested { try? await Task.sleep(for: .milliseconds(50)) }
                if !cancelRequested, next < elements.count { submit(next); next += 1; activeCount += 1; peakActiveCount = max(peakActiveCount, activeCount) }
            }
            return results.compactMap { $0 }
        }
    }
}
