import Foundation
import os
import ConnorGraphAppSupport

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
