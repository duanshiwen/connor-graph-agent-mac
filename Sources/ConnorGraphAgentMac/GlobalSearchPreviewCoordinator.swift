import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

struct GlobalSearchNativePreviewSectionResult: Sendable {
    var kind: NativeSearchSourceKind
    var results: [NativeSearchResult]
    var errorMessage: String?
    var timing: GlobalSearchSectionTiming
}

struct GlobalSearchPreviewCoordinator: Sendable {
    var backend: any NativeSourceSearchBackend
    var timeoutMilliseconds: Int
    var errorMessage: @Sendable (Error) -> String?

    init(
        backend: any NativeSourceSearchBackend,
        timeoutMilliseconds: Int = 250,
        errorMessage: @escaping @Sendable (Error) -> String? = GlobalSearchPreviewCoordinator.defaultErrorMessage(for:)
    ) {
        self.backend = backend
        self.timeoutMilliseconds = timeoutMilliseconds
        self.errorMessage = errorMessage
    }

    func previewResults(
        query: String,
        limitsBySource: [NativeSearchSourceKind: Int]
    ) -> AsyncStream<GlobalSearchNativePreviewSectionResult> {
        let backend = backend
        let timeoutMilliseconds = timeoutMilliseconds
        let errorMessage = errorMessage
        let backendName = String(describing: type(of: backend))
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: GlobalSearchNativePreviewSectionResult.self) { group in
                    for kind in NativeSearchSourceKind.allCases {
                        let limit = limitsBySource[kind] ?? 3
                        group.addTask {
                            let startedAt = Date()
                            do {
                                let results = try await Self.withTimeout(milliseconds: timeoutMilliseconds) {
                                    try await backend.search(NativeSearchQuery(
                                        text: query,
                                        sourceKinds: [kind],
                                        limit: limit,
                                        includeBodySnippets: true,
                                        rankingProfile: .recentFirst
                                    ))
                                }
                                return GlobalSearchNativePreviewSectionResult(
                                    kind: kind,
                                    results: results,
                                    errorMessage: nil,
                                    timing: GlobalSearchSectionTiming(
                                        query: query,
                                        section: GlobalSearchSectionKind(nativeSourceKind: kind).rawValue,
                                        startedAt: startedAt,
                                        endedAt: Date(),
                                        candidateCount: results.count,
                                        returnedCount: results.count,
                                        backend: backendName
                                    )
                                )
                            } catch {
                                return GlobalSearchNativePreviewSectionResult(
                                    kind: kind,
                                    results: [],
                                    errorMessage: errorMessage(error),
                                    timing: GlobalSearchSectionTiming(
                                        query: query,
                                        section: GlobalSearchSectionKind(nativeSourceKind: kind).rawValue,
                                        startedAt: startedAt,
                                        endedAt: Date(),
                                        candidateCount: 0,
                                        returnedCount: 0,
                                        backend: "error:\(String(describing: error))"
                                    )
                                )
                            }
                        }
                    }

                    for await result in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            break
                        }
                        continuation.yield(result)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func defaultErrorMessage(for error: Error) -> String? {
        if error is GlobalSearchTimeoutError { return nil }
        return String(describing: error)
    }

    static func withTimeout<T: Sendable>(milliseconds: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                throw GlobalSearchTimeoutError.hardTimeout(milliseconds: milliseconds)
            }
            guard let value = try await group.next() else { throw GlobalSearchTimeoutError.hardTimeout(milliseconds: milliseconds) }
            group.cancelAll()
            return value
        }
    }
}
