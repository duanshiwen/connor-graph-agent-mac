import Foundation
import ConnorGraphCore
import ConnorGraphStore

public enum PersonMemoryConsoleServiceError: Error, Sendable, Equatable {
    case missingMemoryBinding
    case memoryItemNotFound(String)
    case memoryItemDoesNotBelongToPerson(itemID: String, personID: ContactID)
}

public enum PersonMemoryItemStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case active
    case archived
    case deleted
    case moved
}

public struct PersonMemoryItem: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var personID: ContactID
    public var memoryEntityID: String
    public var predicate: String
    public var text: String
    public var status: PersonMemoryItemStatus
    public var sourceArtifactID: String?
    public var validAt: Date
    public var committedAt: Date
    public var evidenceSpanIDs: [String]

    public init(
        id: String,
        personID: ContactID,
        memoryEntityID: String,
        predicate: String,
        text: String,
        status: PersonMemoryItemStatus = .active,
        sourceArtifactID: String? = nil,
        validAt: Date,
        committedAt: Date,
        evidenceSpanIDs: [String] = []
    ) {
        self.id = id
        self.personID = personID
        self.memoryEntityID = memoryEntityID
        self.predicate = predicate
        self.text = text
        self.status = status
        self.sourceArtifactID = sourceArtifactID
        self.validAt = validAt
        self.committedAt = committedAt
        self.evidenceSpanIDs = evidenceSpanIDs
    }
}

public protocol PersonMemoryConsoleService: Sendable {
    func loadMemoryItems(for profile: PersonProfile, includeInactive: Bool, limit: Int) async throws -> [PersonMemoryItem]
    func activeMemorySummary(for profile: PersonProfile, limit: Int) async throws -> String
    func archiveMemoryItem(id: String, for profile: PersonProfile, now: Date) async throws
    func deleteMemoryItem(id: String, for profile: PersonProfile, now: Date) async throws
}

public final class AppPersonMemoryConsoleService: PersonMemoryConsoleService, @unchecked Sendable {
    public enum MetadataKey {
        public static let personProfileID = "person_profile_id"
        public static let status = "person_memory_status"
        public static let governedAt = "person_memory_governed_at"
    }

    private let store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func loadMemoryItems(for profile: PersonProfile, includeInactive: Bool = false, limit: Int = 100) async throws -> [PersonMemoryItem] {
        guard profile.status == .active,
              let entityID = profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entityID.isEmpty else {
            return []
        }

        let statements = try store.entityStatements(entityID: entityID, limit: limit)
        let items = statements.map { statement in
            makeItem(from: statement, profile: profile, entityID: entityID)
        }
        if includeInactive {
            return items
        }
        return items.filter { $0.status == .active }
    }

    public func activeMemorySummary(for profile: PersonProfile, limit: Int = 8) async throws -> String {
        let items = try await loadMemoryItems(for: profile, includeInactive: false, limit: limit)
        guard !items.isEmpty else { return "" }
        return items.prefix(limit).map { "- \($0.text)" }.joined(separator: "\n")
    }

    public func archiveMemoryItem(id: String, for profile: PersonProfile, now: Date = Date()) async throws {
        try governMemoryItem(id: id, for: profile, status: .archived, now: now)
    }

    public func deleteMemoryItem(id: String, for profile: PersonProfile, now: Date = Date()) async throws {
        try governMemoryItem(id: id, for: profile, status: .deleted, now: now)
    }

    private func governMemoryItem(id: String, for profile: PersonProfile, status: PersonMemoryItemStatus, now: Date) throws {
        guard let entityID = profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines), !entityID.isEmpty else {
            throw PersonMemoryConsoleServiceError.missingMemoryBinding
        }
        guard var statement = try store.entityStatement(id: id) else {
            throw PersonMemoryConsoleServiceError.memoryItemNotFound(id)
        }
        guard statement.entityID == entityID else {
            throw PersonMemoryConsoleServiceError.memoryItemDoesNotBelongToPerson(itemID: id, personID: profile.id)
        }
        if let statementPersonID = statement.metadata[MetadataKey.personProfileID], statementPersonID != profile.id.rawValue {
            throw PersonMemoryConsoleServiceError.memoryItemDoesNotBelongToPerson(itemID: id, personID: profile.id)
        }
        statement.metadata[MetadataKey.personProfileID] = profile.id.rawValue
        statement.metadata[MetadataKey.status] = status.rawValue
        statement.metadata[MetadataKey.governedAt] = ISO8601DateFormatter().string(from: now)
        try store.upsert(entityStatement: statement)
    }

    private func makeItem(from statement: MemoryOSEntityStatement, profile: PersonProfile, entityID: String) -> PersonMemoryItem {
        PersonMemoryItem(
            id: statement.id,
            personID: ContactID(rawValue: statement.metadata[MetadataKey.personProfileID] ?? profile.id.rawValue),
            memoryEntityID: entityID,
            predicate: statement.predicate.rawValue,
            text: statement.text,
            status: status(from: statement.metadata[MetadataKey.status]),
            sourceArtifactID: statement.sourceArtifactID,
            validAt: statement.validAt,
            committedAt: statement.committedAt,
            evidenceSpanIDs: statement.evidenceSpanIDs
        )
    }

    private func status(from rawValue: String?) -> PersonMemoryItemStatus {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else { return .active }
        return PersonMemoryItemStatus(rawValue: rawValue) ?? .active
    }
}
