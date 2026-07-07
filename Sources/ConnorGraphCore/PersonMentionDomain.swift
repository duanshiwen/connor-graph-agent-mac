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
        guard selectedRange.length == 0 else { return nil }
        guard selectedRange.location >= 0, selectedRange.location <= (text as NSString).length else { return nil }
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

    private static let terminatingCharacters: Set<Character> = ["，", "。", "、", ",", ".", "!", "?", "！", "？", ":", "：", ";", "；", "（", "(", ")", "）", "[", "]", "【", "】", "{", "}"]

    private func isValidMentionBoundary(before atIndex: String.Index, in text: String) -> Bool {
        guard atIndex > text.startIndex else { return true }
        let previous = text[text.index(before: atIndex)]
        return previous.isWhitespace || previous.isNewline
    }
}

public struct PersonMentionSearch: Sendable {
    public init() {}

    public func search(query: String, profiles: [PersonProfile], limit: Int = 8) -> [PersonProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let activeProfiles = profiles.filter(\.isActiveForDefaultContext)
        let filtered: [PersonProfile]
        if normalizedQuery.isEmpty {
            filtered = activeProfiles
        } else {
            filtered = activeProfiles.filter { profile in
                searchableTokens(for: profile).contains { token in
                    token.localizedLowercase.contains(normalizedQuery)
                }
            }
        }
        return Array(filtered.sorted(by: sortProfiles).prefix(max(0, limit)))
    }

    private func searchableTokens(for profile: PersonProfile) -> [String] {
        var tokens = [
            profile.displayName,
            profile.givenName,
            profile.familyName,
            profile.organizationName ?? "",
            profile.jobTitle ?? "",
            profile.notes ?? ""
        ]
        tokens.append(contentsOf: profile.aliases)
        tokens.append(contentsOf: profile.emails.map(\.email))
        tokens.append(contentsOf: profile.phones.map(\.number))
        return tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func sortProfiles(_ lhs: PersonProfile, _ rhs: PersonProfile) -> Bool {
        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return lhs.id.rawValue.localizedStandardCompare(rhs.id.rawValue) == .orderedAscending
    }
}

public struct ComposerPersonMentionTextRewriter: Sendable {
    public init() {}

    public func replace(trigger: PersonMentionTrigger, in text: String, with profile: PersonProfile) throws -> PersonMentionReplacement {
        guard let range = Range(trigger.range, in: text) else { throw PersonMentionTextRewriteError.invalidRange }
        let mentionText = "@\(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines))"
        let replacementText = mentionText + " "
        var updatedText = text
        updatedText.replaceSubrange(range, with: replacementText)
        let selectedLocation = trigger.range.location + (replacementText as NSString).length
        let mention = ComposerPersonMention(
            profile: profile,
            mentionText: mentionText,
            range: TextRange(location: trigger.range.location, length: (mentionText as NSString).length)
        )
        return PersonMentionReplacement(
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
