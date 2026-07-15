import Foundation
import os

public enum AppPerformanceLog {
    public static let subsystem = "ConnorGraphAgentMac"
    public static let chatTurnCategory = "ChatTurnPerformance"
    public static let sidebarNavigationCategory = "SidebarNavigationPerformance"
    public static let chatTurnLogger = Logger(subsystem: subsystem, category: chatTurnCategory)
    public static let sidebarNavigationLogger = Logger(subsystem: subsystem, category: sidebarNavigationCategory)

    public struct Duration: Sendable, Equatable {
        public var nanoseconds: UInt64

        public init(nanoseconds: UInt64) {
            self.nanoseconds = nanoseconds
        }

        public var milliseconds: Double {
            Double(nanoseconds) / 1_000_000
        }
    }

    public static func measure<T>(_ operation: () throws -> T) rethrows -> (value: T, duration: Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try operation()
        let elapsed = start.duration(to: clock.now)
        return (value, Duration(nanoseconds: UInt64(elapsed.components.seconds) * 1_000_000_000 + UInt64(elapsed.components.attoseconds / 1_000_000_000)))
    }

    public static func measure(_ operation: () throws -> Void) rethrows -> Duration {
        let (_, duration) = try measure { try operation() }
        return duration
    }

    public static func measure<T>(_ operation: () async throws -> T) async rethrows -> (value: T, duration: Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await operation()
        let elapsed = start.duration(to: clock.now)
        return (value, Duration(nanoseconds: UInt64(elapsed.components.seconds) * 1_000_000_000 + UInt64(elapsed.components.attoseconds / 1_000_000_000)))
    }

    public static func measure(_ operation: () async throws -> Void) async rethrows -> Duration {
        let (_, duration) = try await measure { try await operation() }
        return duration
    }
}
