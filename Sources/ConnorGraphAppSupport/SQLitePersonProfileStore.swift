import Foundation
import SQLite3
import ConnorGraphCore

public protocol PersonProfileStore: Sendable {
    func loadProfiles(includeInactive: Bool) async throws -> [PersonProfile]
    func searchProfiles(query: String, includeInactive: Bool) async throws -> [PersonProfile]
    func profile(id: ContactID) async throws -> PersonProfile?
    func upsert(_ profile: PersonProfile) async throws -> PersonProfile
    func markDeleted(id: ContactID, now: Date) async throws
    func merge(sourceID: ContactID, targetID: ContactID, now: Date) async throws -> PersonProfile
}

public enum SQLitePersonProfileStoreError: Error, LocalizedError, Sendable, Equatable {
    case openFailed(String)
    case sqlite(String)
    case profileNotFound(String)
    case cannotMergeSameProfile

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return message
        case .sqlite(let message): return message
        case .profileNotFound(let id): return "Person profile not found: \(id)"
        case .cannotMergeSameProfile: return "Cannot merge a person profile into itself."
        }
    }
}

public final class SQLitePersonProfileStore: PersonProfileStore, @unchecked Sendable {
    private let db: OpaquePointer
    private let queue = DispatchQueue(label: "ConnorGraphAppSupport.SQLitePersonProfileStore")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let openedDB = db else {
            throw SQLitePersonProfileStoreError.openFailed("Cannot open \(databaseURL.path)")
        }
        self.db = openedDB

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .secondsSince1970

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970

        try Self.configurePragmas(db: openedDB)
        try Self.createTables(db: openedDB)
    }

    deinit {
        queue.sync {
            _ = sqlite3_close(db)
        }
    }

    public func loadProfiles(includeInactive: Bool = false) async throws -> [PersonProfile] {
        try queue.sync {
            try loadProfilesInternal(includeInactive: includeInactive)
        }
    }

    public func searchProfiles(query: String, includeInactive: Bool = false) async throws -> [PersonProfile] {
        try queue.sync {
            let normalized = normalize(query)
            let profiles = try loadProfilesInternal(includeInactive: includeInactive)
            guard !normalized.isEmpty else { return profiles }
            return profiles.filter { profileMatches($0, normalizedQuery: normalized) }
        }
    }

    public func profile(id: ContactID) async throws -> PersonProfile? {
        try queue.sync {
            try profileInternal(id: id)
        }
    }

    public func upsert(_ profile: PersonProfile) async throws -> PersonProfile {
        try queue.sync {
            try executeInternal("BEGIN TRANSACTION;")
        do {
            try upsertInternal(profile)
            try executeInternal("COMMIT;")
            return profile
            } catch {
                try? executeInternal("ROLLBACK;")
                throw error
            }
        }
    }

    public func markDeleted(id: ContactID, now: Date = Date()) async throws {
        try queue.sync {
            guard var profile = try profileInternal(id: id) else {
            throw SQLitePersonProfileStoreError.profileNotFound(id.rawValue)
        }
        profile.status = .deleted
        profile.updatedAt = now
        try executeInternal("BEGIN TRANSACTION;")
        do {
            try upsertInternal(profile)
            try executeInternal("COMMIT;")
            } catch {
                try? executeInternal("ROLLBACK;")
                throw error
            }
        }
    }

    public func merge(sourceID: ContactID, targetID: ContactID, now: Date = Date()) async throws -> PersonProfile {
        try queue.sync {
            guard sourceID != targetID else { throw SQLitePersonProfileStoreError.cannotMergeSameProfile }

            guard var source = try profileInternal(id: sourceID) else {
            throw SQLitePersonProfileStoreError.profileNotFound(sourceID.rawValue)
        }
        guard var target = try profileInternal(id: targetID) else {
            throw SQLitePersonProfileStoreError.profileNotFound(targetID.rawValue)
        }

        target.aliases = mergeAliases(target.aliases + [source.displayName] + source.aliases, excludingPrimaryName: target.displayName)
        target.emails = mergeEmails(target.emails + source.emails)
        target.phones = mergePhones(target.phones + source.phones)
        target.addresses = mergeAddresses(target.addresses + source.addresses)
        target.organizationName = nonEmpty(target.organizationName) ?? nonEmpty(source.organizationName)
        target.jobTitle = nonEmpty(target.jobTitle) ?? nonEmpty(source.jobTitle)
        target.notes = mergeNotes(primary: target.notes, secondary: source.notes)
        target.memoryEntityID = nonEmpty(target.memoryEntityID) ?? nonEmpty(source.memoryEntityID)
        target.memoryStableKey = nonEmpty(target.memoryStableKey) ?? nonEmpty(source.memoryStableKey)
        target.updatedAt = now

        source.status = .merged
        source.mergedIntoID = targetID
        source.updatedAt = now

        try executeInternal("BEGIN TRANSACTION;")
        do {
            try upsertInternal(target)
            try upsertInternal(source)
            try executeInternal("COMMIT;")
            return target
            } catch {
                try? executeInternal("ROLLBACK;")
                throw error
            }
        }
    }

    private static func configurePragmas(db: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL;", db: db)
        try execute("PRAGMA synchronous = NORMAL;", db: db)
        try execute("PRAGMA busy_timeout = 5000;", db: db)
        try execute("PRAGMA temp_store = MEMORY;", db: db)
        try execute("PRAGMA cache_size = -8000;", db: db)
        try execute("PRAGMA foreign_keys = ON;", db: db)
    }

    private static func createTables(db: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS person_profiles (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                normalized_display_name TEXT NOT NULL,
                given_name TEXT,
                family_name TEXT,
                gender TEXT,
                organization_name TEXT,
                job_title TEXT,
                notes TEXT,
                status TEXT NOT NULL,
                merged_into_id TEXT,
                memory_entity_id TEXT,
                memory_stable_key TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                raw_json TEXT NOT NULL
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS person_profile_aliases (
                id TEXT PRIMARY KEY,
                person_id TEXT NOT NULL,
                alias TEXT NOT NULL,
                normalized_alias TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(person_id) REFERENCES person_profiles(id) ON DELETE CASCADE
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS person_profile_emails (
                id TEXT PRIMARY KEY,
                person_id TEXT NOT NULL,
                label TEXT,
                email TEXT NOT NULL,
                normalized_email TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(person_id) REFERENCES person_profiles(id) ON DELETE CASCADE
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS person_profile_phones (
                id TEXT PRIMARY KEY,
                person_id TEXT NOT NULL,
                label TEXT,
                number TEXT NOT NULL,
                normalized_number TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(person_id) REFERENCES person_profiles(id) ON DELETE CASCADE
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS person_profile_addresses (
                id TEXT PRIMARY KEY,
                person_id TEXT NOT NULL,
                label TEXT,
                value TEXT NOT NULL,
                normalized_value TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(person_id) REFERENCES person_profiles(id) ON DELETE CASCADE
            );
        """, db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_profiles_status ON person_profiles(status);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_profiles_display_name ON person_profiles(normalized_display_name);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_profiles_org ON person_profiles(organization_name);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_profiles_updated_at ON person_profiles(updated_at DESC);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_aliases_person_id ON person_profile_aliases(person_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_aliases_normalized ON person_profile_aliases(normalized_alias);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_emails_person_id ON person_profile_emails(person_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_emails_normalized ON person_profile_emails(normalized_email);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_phones_person_id ON person_profile_phones(person_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_phones_normalized ON person_profile_phones(normalized_number);", db: db)
    }

    private static func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLitePersonProfileStoreError.sqlite(message)
        }
    }

    private func loadProfilesInternal(includeInactive: Bool) throws -> [PersonProfile] {
        let sql: String
        if includeInactive {
            sql = "SELECT raw_json FROM person_profiles ORDER BY updated_at DESC, display_name ASC;"
        } else {
            sql = "SELECT raw_json FROM person_profiles WHERE status IN ('active', 'pending') ORDER BY updated_at DESC, display_name ASC;"
        }
        return try queryJSONProfiles(sql: sql)
    }

    private func profileInternal(id: ContactID) throws -> PersonProfile? {
        let sql = "SELECT raw_json FROM person_profiles WHERE id = '\(escape(id.rawValue))' LIMIT 1;"
        return try queryJSONProfiles(sql: sql).first
    }

    private func upsertInternal(_ profile: PersonProfile) throws {
        let rawJSON = String(decoding: try encoder.encode(profile), as: UTF8.self)
        try executePrepared(
            """
            INSERT OR REPLACE INTO person_profiles (
                id, display_name, normalized_display_name, given_name, family_name, gender,
                organization_name, job_title, notes, status, merged_into_id, memory_entity_id,
                memory_stable_key, created_at, updated_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(profile.id.rawValue),
                .text(profile.displayName),
                .text(normalize(profile.displayName)),
                .text(profile.givenName),
                .text(profile.familyName),
                .optionalText(profile.gender),
                .optionalText(profile.organizationName),
                .optionalText(profile.jobTitle),
                .optionalText(profile.notes),
                .text(profile.status.rawValue),
                .optionalText(profile.mergedIntoID?.rawValue),
                .optionalText(profile.memoryEntityID),
                .optionalText(profile.memoryStableKey),
                .text(isoString(profile.createdAt)),
                .text(isoString(profile.updatedAt)),
                .text(rawJSON)
            ]
        )

        try replaceChildRows(for: profile)
    }

    private func replaceChildRows(for profile: PersonProfile) throws {
        let personID = escape(profile.id.rawValue)
        try executeInternal("DELETE FROM person_profile_aliases WHERE person_id = '\(personID)';")
        try executeInternal("DELETE FROM person_profile_emails WHERE person_id = '\(personID)';")
        try executeInternal("DELETE FROM person_profile_phones WHERE person_id = '\(personID)';")
        try executeInternal("DELETE FROM person_profile_addresses WHERE person_id = '\(personID)';")

        for alias in profile.aliases where !normalize(alias).isEmpty {
            try executePrepared(
                "INSERT INTO person_profile_aliases (id, person_id, alias, normalized_alias, created_at) VALUES (?, ?, ?, ?, ?);",
                bindings: [.text(UUID().uuidString), .text(profile.id.rawValue), .text(alias), .text(normalize(alias)), .text(isoString(profile.createdAt))]
            )
        }
        for email in profile.emails where !normalize(email.email).isEmpty {
            try executePrepared(
                "INSERT INTO person_profile_emails (id, person_id, label, email, normalized_email, created_at) VALUES (?, ?, ?, ?, ?, ?);",
                bindings: [.text("\(profile.id.rawValue):email:\(email.id)"), .text(profile.id.rawValue), .optionalText(email.label), .text(email.email), .text(normalize(email.email)), .text(isoString(profile.createdAt))]
            )
        }
        for phone in profile.phones where !normalize(phone.number).isEmpty {
            try executePrepared(
                "INSERT INTO person_profile_phones (id, person_id, label, number, normalized_number, created_at) VALUES (?, ?, ?, ?, ?, ?);",
                bindings: [.text("\(profile.id.rawValue):phone:\(phone.id)"), .text(profile.id.rawValue), .optionalText(phone.label), .text(phone.number), .text(normalizePhone(phone.number)), .text(isoString(profile.createdAt))]
            )
        }
        for address in profile.addresses where !normalize(address.value).isEmpty {
            try executePrepared(
                "INSERT INTO person_profile_addresses (id, person_id, label, value, normalized_value, created_at) VALUES (?, ?, ?, ?, ?, ?);",
                bindings: [.text("\(profile.id.rawValue):address:\(address.id)"), .text(profile.id.rawValue), .optionalText(address.label), .text(address.value), .text(normalize(address.value)), .text(isoString(profile.createdAt))]
            )
        }
    }

    private func queryJSONProfiles(sql: String) throws -> [PersonProfile] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var profiles: [PersonProfile] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let rawJSON = String(cString: cString)
            profiles.append(try decoder.decode(PersonProfile.self, from: Data(rawJSON.utf8)))
        }
        return profiles
    }

    private func executeInternal(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLitePersonProfileStoreError.sqlite(message)
        }
    }

    private enum Binding {
        case text(String)
        case optionalText(String?)
    }

    private func executePrepared(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .optionalText(let value):
                if let value {
                    result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            }
            guard result == SQLITE_OK else { throw lastError() }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func lastError() -> SQLitePersonProfileStoreError {
        SQLitePersonProfileStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }

    private func profileMatches(_ profile: PersonProfile, normalizedQuery: String) -> Bool {
        let haystacks: [String] = [
            profile.displayName,
            profile.givenName,
            profile.familyName,
            profile.gender ?? "",
            profile.organizationName ?? "",
            profile.jobTitle ?? "",
            profile.notes ?? "",
            profile.aliases.joined(separator: " "),
            profile.emails.map(\.email).joined(separator: " "),
            profile.phones.map(\.number).joined(separator: " "),
            profile.addresses.map(\.value).joined(separator: " ")
        ]
        return haystacks.contains { normalize($0).contains(normalizedQuery) }
    }

    private func mergeAliases(_ aliases: [String], excludingPrimaryName displayName: String) -> [String] {
        var seen: Set<String> = [normalize(displayName)]
        var result: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private func mergeEmails(_ emails: [ContactEmailAddress]) -> [ContactEmailAddress] {
        var seen: Set<String> = []
        var result: [ContactEmailAddress] = []
        for email in emails {
            let key = normalize(email.email)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(email)
        }
        return result
    }

    private func mergePhones(_ phones: [PersonPhoneNumber]) -> [PersonPhoneNumber] {
        var seen: Set<String> = []
        var result: [PersonPhoneNumber] = []
        for phone in phones {
            let key = normalizePhone(phone.number)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(phone)
        }
        return result
    }

    private func mergeAddresses(_ addresses: [PersonPostalAddress]) -> [PersonPostalAddress] {
        var seen: Set<String> = []
        var result: [PersonPostalAddress] = []
        for address in addresses {
            let key = normalize(address.value)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(address)
        }
        return result
    }

    private func mergeNotes(primary: String?, secondary: String?) -> String? {
        let first = nonEmpty(primary)
        let second = nonEmpty(secondary)
        switch (first, second) {
        case let (first?, second?) where first != second:
            return "\(first)\n\n\(second)"
        case let (first?, _):
            return first
        case let (_, second?):
            return second
        default:
            return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizePhone(_ value: String) -> String {
        value.filter { $0.isNumber || $0 == "+" }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func isoString(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
