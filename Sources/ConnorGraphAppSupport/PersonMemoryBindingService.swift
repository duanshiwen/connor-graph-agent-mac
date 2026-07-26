import Foundation
import ConnorGraphCore

public enum PersonMemoryGovernanceEventKind: String, Codable, Sendable, Equatable, Hashable {
    case bound
    case merged
    case deleted
}

public struct PersonMemoryGovernanceEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var kind: PersonMemoryGovernanceEventKind
    public var personID: ContactID
    public var targetPersonID: ContactID?
    public var memoryEntityID: String?
    public var memoryStableKey: String?
    public var statement: String
    public var occurredAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: PersonMemoryGovernanceEventKind,
        personID: ContactID,
        targetPersonID: ContactID? = nil,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil,
        statement: String,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.personID = personID
        self.targetPersonID = targetPersonID
        self.memoryEntityID = memoryEntityID
        self.memoryStableKey = memoryStableKey
        self.statement = statement
        self.occurredAt = occurredAt
    }
}

public protocol PersonMemoryGovernanceSink: Sendable {
    func record(_ event: PersonMemoryGovernanceEvent) async throws
}

public final class InMemoryPersonMemoryGovernanceSink: PersonMemoryGovernanceSink, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ConnorGraphAppSupport.InMemoryPersonMemoryGovernanceSink")
    private var storedEvents: [PersonMemoryGovernanceEvent] = []

    public init() {}

    public var events: [PersonMemoryGovernanceEvent] {
        queue.sync { storedEvents }
    }

    public func record(_ event: PersonMemoryGovernanceEvent) async throws {
        queue.sync {
            storedEvents.append(event)
        }
    }
}

public protocol PersonMemoryBindingService: Sendable {
    func ensureBinding(for profile: PersonProfile, now: Date) async throws -> PersonProfile
    func mergeBinding(source: PersonProfile, target: PersonProfile, now: Date) async throws -> PersonProfile
    func markDeleted(profile: PersonProfile, now: Date) async throws
}

public final class AppPersonMemoryBindingService: PersonMemoryBindingService, @unchecked Sendable {
    private let governanceSink: any PersonMemoryGovernanceSink

    public init(governanceSink: any PersonMemoryGovernanceSink) {
        self.governanceSink = governanceSink
    }

    public func ensureBinding(for profile: PersonProfile, now: Date = Date()) async throws -> PersonProfile {
        if hasCompleteBinding(profile) {
            return profile
        }

        var bound = profile
        let stableKey = Self.stableKey(for: profile.id)
        let entityID = Self.entityID(forStableKey: stableKey)
        bound.memoryStableKey = stableKey
        bound.memoryEntityID = entityID
        bound.updatedAt = now

        try await governanceSink.record(PersonMemoryGovernanceEvent(
            kind: .bound,
            personID: profile.id,
            memoryEntityID: entityID,
            memoryStableKey: stableKey,
            statement: "\(profile.displayName) is bound to Person Registry profile \(profile.id.rawValue) as active person memory context.",
            occurredAt: now
        ))

        return bound
    }

    public func mergeBinding(source: PersonProfile, target: PersonProfile, now: Date = Date()) async throws -> PersonProfile {
        let boundTarget = try await ensureBinding(for: target, now: now)
        let sourceStableKey = source.memoryStableKey ?? Self.stableKey(for: source.id)
        let sourceEntityID = source.memoryEntityID ?? Self.entityID(forStableKey: sourceStableKey)

        try await governanceSink.record(PersonMemoryGovernanceEvent(
            kind: .merged,
            personID: source.id,
            targetPersonID: target.id,
            memoryEntityID: sourceEntityID,
            memoryStableKey: sourceStableKey,
            statement: "\(source.displayName) was merged into \(target.displayName); the merged source person is not active retrieval context and should redirect to \(target.displayName).",
            occurredAt: now
        ))

        return boundTarget
    }

    public func markDeleted(profile: PersonProfile, now: Date = Date()) async throws {
        let stableKey = profile.memoryStableKey ?? Self.stableKey(for: profile.id)
        let entityID = profile.memoryEntityID ?? Self.entityID(forStableKey: stableKey)
        try await governanceSink.record(PersonMemoryGovernanceEvent(
            kind: .deleted,
            personID: profile.id,
            memoryEntityID: entityID,
            memoryStableKey: stableKey,
            statement: "\(profile.displayName) is a deleted person and is not active retrieval context for LLM use.",
            occurredAt: now
        ))
    }

    public static func stableKey(for id: ContactID) -> String {
        "person-profile:\(id.rawValue)"
    }

    public static func entityID(forStableKey stableKey: String) -> String {
        "person:\(stableKey)"
    }

    private func hasCompleteBinding(_ profile: PersonProfile) -> Bool {
        guard let memoryStableKey = profile.memoryStableKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              let memoryEntityID = profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !memoryStableKey.isEmpty && !memoryEntityID.isEmpty
    }
}
