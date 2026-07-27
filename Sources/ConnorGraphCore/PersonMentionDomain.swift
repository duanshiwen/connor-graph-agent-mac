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
        self.mentionText = mentionText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (normalizedDisplayName.isEmpty ? "@person" : "@\(normalizedDisplayName)")
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

public struct PersonMention: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var personID: ContactID
    public var displayName: String
    public var insertedText: String

    public init(
        id: String = UUID().uuidString,
        personID: ContactID,
        displayName: String,
        insertedText: String
    ) {
        self.id = id
        self.personID = personID
        self.displayName = displayName
        self.insertedText = insertedText
    }
}

public struct PersonMentionTrigger: Sendable, Equatable, Hashable {
    public var query: String
    public var range: NSRange

    public init(query: String, range: NSRange) {
        self.query = query
        self.range = range
    }
}

public struct PersonMentionReplacement: Sendable, Equatable, Hashable {
    public var text: String
    public var mention: PersonMention
    public var selectedRange: NSRange

    public init(text: String, mention: PersonMention, selectedRange: NSRange) {
        self.text = text
        self.mention = mention
        self.selectedRange = selectedRange
    }
}

public struct ComposerPersonMentionReplacement: Sendable, Equatable, Hashable {
    public var text: String
    public var mention: ComposerPersonMention
    public var selectedRange: NSRange

    public init(text: String, mention: ComposerPersonMention, selectedRange: NSRange) {
        self.text = text
        self.mention = mention
        self.selectedRange = selectedRange
    }
}

public enum PersonMentionTextRewriteError: Error, Sendable, Equatable {
    case invalidRange
}

public struct PersonMentionTriggerDetector: Sendable {
    public init() {}

    public func trigger(in text: String, selectedRange: NSRange) -> PersonMentionTrigger? {
        guard selectedRange.length == 0,
              selectedRange.location >= 0,
              selectedRange.location <= text.utf16.count else { return nil }
        let cursor = String.Index(utf16Offset: selectedRange.location, in: text)

        var index = cursor
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            if character == "@" {
                guard isValidMentionBoundary(before: previous, in: text) else { return nil }
                let query = String(text[text.index(after: previous)..<cursor])
                guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
                let location = previous.utf16Offset(in: text)
                return PersonMentionTrigger(
                    query: query,
                    range: NSRange(location: location, length: selectedRange.location - location)
                )
            }
            if character.isWhitespace || character.isNewline || Self.terminatingCharacters.contains(character) {
                return nil
            }
            index = previous
        }
        return nil
    }

    private static let terminatingCharacters: Set<Character> = [
        "，", "。", "、", ",", ".", "!", "?", "！", "？", ":", "：", ";", "；",
        "（", "(", ")", "）", "[", "]", "【", "】", "{", "}"
    ]

    private func isValidMentionBoundary(before atIndex: String.Index, in text: String) -> Bool {
        guard atIndex > text.startIndex else { return true }
        let previous = text[text.index(before: atIndex)]
        return previous.isWhitespace || previous.isNewline
    }
}

public struct PersonMentionSearch: Sendable {
    public init() {}

    public func search(query: String, profiles: [PersonProfile], limit: Int = 8) -> [PersonProfile] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let active = profiles.filter(\.isActiveForDefaultContext)
        let activeByID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let matches: [PersonProfile]
        if normalized.isEmpty {
            matches = active
        } else {
            var matchedByID: [ContactID: PersonProfile] = [:]
            for profile in active where profileMatches(profile, normalizedQuery: normalized) {
                matchedByID[profile.id] = profile
            }
            for merged in profiles where merged.status == .merged {
                guard let targetID = merged.mergedIntoID,
                      let target = activeByID[targetID],
                      profileMatches(merged, normalizedQuery: normalized) else { continue }
                matchedByID[target.id] = target
            }
            matches = Array(matchedByID.values)
        }
        return Array(matches.sorted(by: sortProfiles).prefix(max(0, limit)))
    }

    private func profileMatches(_ profile: PersonProfile, normalizedQuery: String) -> Bool {
        let tokens = [
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
        return tokens.contains { $0.localizedLowercase.contains(normalizedQuery) }
    }

    private func sortProfiles(_ lhs: PersonProfile, _ rhs: PersonProfile) -> Bool {
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return lhs.id.rawValue.localizedStandardCompare(rhs.id.rawValue) == .orderedAscending
    }
}

public struct PersonMentionTextRewriter: Sendable {
    public init() {}

    public func replace(
        trigger: PersonMentionTrigger,
        in text: String,
        with profile: PersonProfile
    ) throws -> PersonMentionReplacement {
        guard let range = Range(trigger.range, in: text) else {
            throw PersonMentionTextRewriteError.invalidRange
        }
        let insertedText = "@\(profile.displayName)"
        let replacementText = insertedText + " "
        var updated = text
        updated.replaceSubrange(range, with: replacementText)
        let location = trigger.range.location + replacementText.utf16.count
        let mention = PersonMention(
            personID: profile.id,
            displayName: profile.displayName,
            insertedText: insertedText
        )
        return PersonMentionReplacement(
            text: updated,
            mention: mention,
            selectedRange: NSRange(location: location, length: 0)
        )
    }
}

public struct ComposerPersonMentionTextRewriter: Sendable {
    public init() {}

    public func replace(
        trigger: PersonMentionTrigger,
        in text: String,
        with profile: PersonProfile
    ) throws -> ComposerPersonMentionReplacement {
        guard let range = Range(trigger.range, in: text) else {
            throw PersonMentionTextRewriteError.invalidRange
        }
        let mentionText = "@\(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines))"
        let replacementText = mentionText + " "
        var updatedText = text
        updatedText.replaceSubrange(range, with: replacementText)
        let selectedLocation = trigger.range.location + replacementText.utf16.count
        let mention = ComposerPersonMention(
            profile: profile,
            mentionText: mentionText,
            range: TextRange(location: trigger.range.location, length: mentionText.utf16.count)
        )
        return ComposerPersonMentionReplacement(
            text: updatedText,
            mention: mention,
            selectedRange: NSRange(location: selectedLocation, length: 0)
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
        self.mentionText = mentionText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (normalizedDisplayName.isEmpty ? "@person" : "@\(normalizedDisplayName)")
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
