import Foundation

public struct TextRange: Codable, Sendable, Equatable, Hashable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }
}

public struct PersonReference: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { personID.rawValue }
    public var personID: ContactID
    public var displayName: String
    public var mentionText: String
    public var status: PersonProfileStatus?
    public var mergedIntoID: ContactID?
    public var memoryEntityID: String?
    public var memoryStableKey: String?

    public init(
        personID: ContactID,
        displayName: String,
        mentionText: String? = nil,
        status: PersonProfileStatus? = nil,
        mergedIntoID: ContactID? = nil,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil
    ) {
        self.personID = personID
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = normalizedDisplayName
        self.mentionText = mentionText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (normalizedDisplayName.isEmpty ? "@person" : "@\(normalizedDisplayName)")
        self.status = status
        self.mergedIntoID = mergedIntoID
        self.memoryEntityID = memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.memoryStableKey = memoryStableKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public init(profile: PersonProfile, mentionText: String? = nil) {
        self.init(
            personID: profile.id,
            displayName: profile.displayName,
            mentionText: mentionText,
            status: profile.status,
            mergedIntoID: profile.mergedIntoID,
            memoryEntityID: profile.memoryEntityID,
            memoryStableKey: profile.memoryStableKey
        )
    }
}

public struct ComposerPersonMention: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var personID: ContactID
    public var displayName: String
    public var mentionText: String
    public var range: TextRange
    public var status: PersonProfileStatus?
    public var mergedIntoID: ContactID?
    public var memoryEntityID: String?
    public var memoryStableKey: String?

    public init(
        id: String = UUID().uuidString,
        personID: ContactID,
        displayName: String,
        mentionText: String? = nil,
        range: TextRange,
        status: PersonProfileStatus? = nil,
        mergedIntoID: ContactID? = nil,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil
    ) {
        self.id = id
        self.personID = personID
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = normalizedDisplayName
        self.mentionText = mentionText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (normalizedDisplayName.isEmpty ? "@person" : "@\(normalizedDisplayName)")
        self.range = range
        self.status = status
        self.mergedIntoID = mergedIntoID
        self.memoryEntityID = memoryEntityID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.memoryStableKey = memoryStableKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public init(profile: PersonProfile, mentionText: String? = nil, range: TextRange) {
        self.init(
            personID: profile.id,
            displayName: profile.displayName,
            mentionText: mentionText,
            range: range,
            status: profile.status,
            mergedIntoID: profile.mergedIntoID,
            memoryEntityID: profile.memoryEntityID,
            memoryStableKey: profile.memoryStableKey
        )
    }

    public var personReference: PersonReference {
        PersonReference(
            personID: personID,
            displayName: displayName,
            mentionText: mentionText,
            status: status,
            mergedIntoID: mergedIntoID,
            memoryEntityID: memoryEntityID,
            memoryStableKey: memoryStableKey
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
