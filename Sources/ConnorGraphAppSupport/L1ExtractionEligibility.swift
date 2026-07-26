import Foundation

public final class L1ExtractionEligibility: @unchecked Sendable {
    public static let shared = L1ExtractionEligibility()
    private let lock = NSLock()
    private var leaseExpiresAt: Date?

    private init() {}

    public func update(granted: Bool, expiresAt: Date?) {
        lock.lock(); defer { lock.unlock() }
        leaseExpiresAt = granted ? expiresAt : nil
    }

    public func canRun(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return leaseExpiresAt.map { $0 > now } ?? false
    }
}
