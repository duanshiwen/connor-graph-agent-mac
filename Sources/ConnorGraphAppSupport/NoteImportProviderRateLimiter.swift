import Foundation
import ConnorGraphCore

public struct NoteImportProviderKey: Hashable, Sendable, Codable {
    public var connection: String; public var provider: String; public var model: String
    public init(connection: String, provider: String, model: String) { self.connection = connection; self.provider = provider; self.model = model }
}

public struct NoteImportRetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int; public var initialDelay: TimeInterval; public var maximumDelay: TimeInterval
    public init(maxAttempts: Int = 5, initialDelay: TimeInterval = 1, maximumDelay: TimeInterval = 60) { self.maxAttempts = max(maxAttempts, 1); self.initialDelay = max(initialDelay, 0); self.maximumDelay = max(maximumDelay, initialDelay) }
    public func delay(attempt: Int, retryAfter: TimeInterval? = nil, random: Double = 0.5) -> TimeInterval {
        if let retryAfter { return min(max(retryAfter, 0), maximumDelay) }
        let ceiling = min(initialDelay * pow(2, Double(max(attempt - 1, 0))), maximumDelay)
        return ceiling * min(max(random, 0), 1)
    }
}

public enum NoteImportProviderFailure: Error, Sendable, Equatable {
    case rateLimited(retryAfter: TimeInterval?)
    case transient(String)
    case authenticationRequired
    case contextExceeded
    case policyDenied

    public var isRetryable: Bool { switch self { case .rateLimited, .transient: true; default: false } }
    public var code: NoteImportErrorCode { switch self { case .rateLimited: .llmRateLimited; case .contextExceeded: .llmContextExceeded; default: .llmUnavailable } }
}

public actor NoteImportProviderRateLimiter {
    public struct Limits: Sendable, Equatable { public var maxConcurrent: Int; public var requestsPerMinute: Int; public init(maxConcurrent: Int = 1, requestsPerMinute: Int = 60) { self.maxConcurrent = min(max(maxConcurrent, 1), 3); self.requestsPerMinute = max(requestsPerMinute, 1) } }
    private struct State { var active = 0; var starts: [Date] = []; var blockedUntil: Date? }
    private var limits: [NoteImportProviderKey: Limits] = [:]; private var states: [NoteImportProviderKey: State] = [:]
    public init() {}
    public func configure(_ value: Limits, for key: NoteImportProviderKey) { limits[key] = value }
    public func acquire(_ key: NoteImportProviderKey, now: Date = Date()) -> TimeInterval? {
        let limit = limits[key] ?? .init(); var state = states[key] ?? State(); state.starts.removeAll { now.timeIntervalSince($0) >= 60 }
        if let blocked = state.blockedUntil, blocked > now { states[key] = state; return blocked.timeIntervalSince(now) }
        guard state.active < limit.maxConcurrent, state.starts.count < limit.requestsPerMinute else { states[key] = state; return 0.05 }
        state.active += 1; state.starts.append(now); states[key] = state; return nil
    }
    public func release(_ key: NoteImportProviderKey) { var state = states[key] ?? State(); state.active = max(state.active - 1, 0); states[key] = state }
    public func block(_ key: NoteImportProviderKey, retryAfter: TimeInterval, now: Date = Date()) { var state = states[key] ?? State(); state.blockedUntil = now.addingTimeInterval(max(retryAfter, 0)); states[key] = state }
    public func activeCount(_ key: NoteImportProviderKey) -> Int { states[key]?.active ?? 0 }
}
