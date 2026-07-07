import Foundation
import ConnorGraphCore
import ConnorGraphStore

public enum PersonMemoryConsoleServiceError: Error, Sendable, Equatable {
    case missingMemoryBinding
    case targetPersonIsNotActive(ContactID)
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
    func moveMemoryItem(id: String, from source: PersonProfile, to target: PersonProfile, now: Date) async throws -> PersonMemoryItem
    func mergePersonMemory(source: PersonProfile, target: PersonProfile, now: Date) async throws -> [PersonMemoryItem]
    func deletePersonMemory(for profile: PersonProfile, now: Date) async throws
}

public final class AppPersonMemoryConsoleService: PersonMemoryConsoleService, @unchecked Sendable {
    public enum MetadataKey {
        public static let personProfileID = "person_profile_id"
        public static let status = "person_memory_status"
        public static let governedAt = "person_memory_governed_at"
        public static let movedToProfileID = "person_memory_moved_to_profile_id"
        public static let movedFromProfileID = "person_memory_moved_from_profile_id"
        public static let movedFromStatementID = "person_memory_moved_from_statement_id"
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

    public func moveMemoryItem(id: String, from source: PersonProfile, to target: PersonProfile, now: Date = Date()) async throws -> PersonMemoryItem {
        guard let sourceStatement = try store.entityStatement(id: id) else {
            throw PersonMemoryConsoleServiceError.memoryItemNotFound(id)
        }
        return try move(statement: sourceStatement, from: source, to: target, now: now)
    }

    public func mergePersonMemory(source: PersonProfile, target: PersonProfile, now: Date = Date()) async throws -> [PersonMemoryItem] {
        let activeItems = try await loadMemoryItems(for: source, includeInactive: false)
        var moved: [PersonMemoryItem] = []
        for item in activeItems {
            moved.append(try await moveMemoryItem(id: item.id, from: source, to: target, now: now))
        }
        return moved
    }

    public func deletePersonMemory(for profile: PersonProfile, now: Date = Date()) async throws {
        let activeItems = try await loadMemoryItems(for: profile, includeInactive: false)
        for item in activeItems {
            try await deleteMemoryItem(id: item.id, for: profile, now: now)
        }
    }

    private func move(statement sourceStatement: MemoryOSEntityStatement, from source: PersonProfile, to target: PersonProfile, now: Date) throws -> PersonMemoryItem {
        guard target.isActiveForDefaultContext else {
            throw PersonMemoryConsoleServiceError.targetPersonIsNotActive(target.id)
        }
        guard let targetEntityID = target.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines), !targetEntityID.isEmpty else {
            throw PersonMemoryConsoleServiceError.missingMemoryBinding
        }
        var sourceStatement = sourceStatement
        try validate(statement: sourceStatement, belongsTo: source, id: sourceStatement.id)

        sourceStatement.metadata[MetadataKey.personProfileID] = source.id.rawValue
        sourceStatement.metadata[MetadataKey.status] = PersonMemoryItemStatus.moved.rawValue
        sourceStatement.metadata[MetadataKey.movedToProfileID] = target.id.rawValue
        sourceStatement.metadata[MetadataKey.governedAt] = ISO8601DateFormatter().string(from: now)
        try store.upsert(entityStatement: sourceStatement)

        var targetMetadata = sourceStatement.metadata
        targetMetadata[MetadataKey.personProfileID] = target.id.rawValue
        targetMetadata[MetadataKey.status] = PersonMemoryItemStatus.active.rawValue
        targetMetadata[MetadataKey.movedFromProfileID] = source.id.rawValue
        targetMetadata[MetadataKey.movedFromStatementID] = sourceStatement.id
        targetMetadata[MetadataKey.governedAt] = ISO8601DateFormatter().string(from: now)
        let targetStatement = MemoryOSEntityStatement(
            id: "person-memory-move:\(sourceStatement.id):\(UUID().uuidString)",
            entityID: targetEntityID,
            predicate: sourceStatement.predicate,
            objectEntityID: sourceStatement.objectEntityID,
            text: sourceStatement.text,
            assertionKind: sourceStatement.assertionKind,
            confidence: sourceStatement.confidence,
            validAt: sourceStatement.validAt,
            committedAt: now,
            evidenceSpanIDs: sourceStatement.evidenceSpanIDs,
            sourceArtifactID: sourceStatement.sourceArtifactID,
            metadata: targetMetadata
        )
        try store.upsert(entityStatement: targetStatement)
        return makeItem(from: targetStatement, profile: target, entityID: targetEntityID)
    }

    private func governMemoryItem(id: String, for profile: PersonProfile, status: PersonMemoryItemStatus, now: Date) throws {
        guard let entityID = profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines), !entityID.isEmpty else {
            throw PersonMemoryConsoleServiceError.missingMemoryBinding
        }
        guard var statement = try store.entityStatement(id: id) else {
            throw PersonMemoryConsoleServiceError.memoryItemNotFound(id)
        }
        try validate(statement: statement, belongsTo: profile, id: id, expectedEntityID: entityID)
        statement.metadata[MetadataKey.personProfileID] = profile.id.rawValue
        statement.metadata[MetadataKey.status] = status.rawValue
        statement.metadata[MetadataKey.governedAt] = ISO8601DateFormatter().string(from: now)
        try store.upsert(entityStatement: statement)
    }

    private func validate(statement: MemoryOSEntityStatement, belongsTo profile: PersonProfile, id: String, expectedEntityID: String? = nil) throws {
        let entityID = expectedEntityID ?? profile.memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !entityID.isEmpty, statement.entityID == entityID else {
            throw PersonMemoryConsoleServiceError.memoryItemDoesNotBelongToPerson(itemID: id, personID: profile.id)
        }
        if let statementPersonID = statement.metadata[MetadataKey.personProfileID], statementPersonID != profile.id.rawValue {
            throw PersonMemoryConsoleServiceError.memoryItemDoesNotBelongToPerson(itemID: id, personID: profile.id)
        }
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
