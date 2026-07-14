import Foundation
import os
import ConnorGraphAppSupport

@MainActor
enum AppStartupPerformance {
    private static let signposter = OSSignposter(
        subsystem: AppPerformanceLog.subsystem,
        category: "AppStartup"
    )

    static func measure<T>(_ name: StaticString, operation: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    static func measure<T>(_ name: StaticString, operation: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

final class AppMainActorStallMonitor {
    struct Configuration: Sendable, Equatable {
        var intervalNanoseconds: UInt64
        var warningThresholdMilliseconds: Double

        static let debugDefault = Configuration(
            intervalNanoseconds: 250_000_000,
            warningThresholdMilliseconds: 500
        )
    }

    private let configuration: Configuration
    private let logger = Logger(subsystem: AppPerformanceLog.subsystem, category: "MainActorStall")
    private var task: Task<Void, Never>?

    init(configuration: Configuration = .debugDefault) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    func start() {
        guard task == nil else { return }
        let configuration = configuration
        let logger = logger
        task = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: configuration.intervalNanoseconds)
                let start = ContinuousClock.now
                await MainActor.run {}
                let elapsed = start.duration(to: ContinuousClock.now)
                let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                if milliseconds >= configuration.warningThresholdMilliseconds {
                    logger.warning("MainActor stall detected: \(milliseconds, privacy: .public)ms")
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
