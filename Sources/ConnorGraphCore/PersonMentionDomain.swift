import Foundation

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

public enum PersonMentionTextRewriteError: Error, Sendable, Equatable {
    case invalidRange
}

public struct PersonMentionTriggerDetector: Sendable {
    public init() {}

    public func trigger(in text: String, selectedRange: NSRange) -> PersonMentionTrigger? {
        guard selectedRange.length == 0 else { return nil }
        guard selectedRange.location >= 0, selectedRange.location <= text.utf16.count else { return nil }
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
            if character.isWhitespace || character.isNewline || Self.terminatingScalars.contains(character) {
                return nil
            }
            index = previous
        }
        return nil
    }

    private static let terminatingScalars: Set<Character> = ["，", "。", "、", ",", ".", "!", "?", "！", "？", ":", "：", ";", "；", "（", "(", ")", "）"]

    private func isValidMentionBoundary(before atIndex: String.Index, in text: String) -> Bool {
        guard atIndex > text.startIndex else { return true }
        let previous = text[text.index(before: atIndex)]
        return previous.isWhitespace || previous.isNewline
    }
}

public struct PersonMentionTextRewriter: Sendable {
    public init() {}

    public func replace(trigger: PersonMentionTrigger, in text: String, with profile: PersonProfile) throws -> PersonMentionReplacement {
        guard let range = Range(trigger.range, in: text) else { throw PersonMentionTextRewriteError.invalidRange }
        let insertedText = "@\(profile.displayName)"
        let replacementText = insertedText + " "
        var updated = text
        updated.replaceSubrange(range, with: replacementText)
        let location = trigger.range.location + replacementText.utf16.count
        let mention = PersonMention(personID: profile.id, displayName: profile.displayName, insertedText: insertedText)
        return PersonMentionReplacement(text: updated, mention: mention, selectedRange: NSRange(location: location, length: 0))
    }
}

public struct PersonMentionSearch: Sendable {
    public init() {}

    public func search(query: String, profiles: [PersonProfile], limit: Int = 8) -> [PersonProfile] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        return Array(matches.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.prefix(limit))
    }

    private func profileMatches(_ profile: PersonProfile, normalizedQuery: String) -> Bool {
        [
            profile.displayName,
            profile.givenName,
            profile.familyName,
            profile.organizationName ?? "",
            profile.jobTitle ?? "",
            profile.aliases.joined(separator: " "),
            profile.emails.map(\.email).joined(separator: " ")
        ].contains { $0.lowercased().contains(normalizedQuery) }
    }
}
