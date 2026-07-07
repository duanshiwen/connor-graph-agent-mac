import Foundation
import ConnorGraphCore

struct ComposerPersonMentionResolver: Sendable {
    func validatedMentions(in text: String, mentions: [ComposerPersonMention]) -> [ComposerPersonMention] {
        mentions.filter { mention in
            guard let range = Range(NSRange(location: mention.range.location, length: mention.range.length), in: text) else { return false }
            return String(text[range]) == mention.mentionText
        }
    }

    func personReferences(in text: String, mentions: [ComposerPersonMention]) -> [PersonReference] {
        var seen = Set<ContactID>()
        var references: [PersonReference] = []
        for mention in validatedMentions(in: text, mentions: mentions) {
            guard !seen.contains(mention.personID) else { continue }
            seen.insert(mention.personID)
            references.append(mention.personReference)
        }
        return references
    }

    func appendingMention(
        profile: PersonProfile,
        to text: String
    ) -> (text: String, mention: ComposerPersonMention) {
        let mentionText = "@\(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines))"
        let prefix: String
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") || text.hasSuffix("\t") {
            prefix = ""
        } else {
            prefix = " "
        }
        let insertion = prefix + mentionText
        let location = (text as NSString).length + (prefix as NSString).length
        let updatedText = text + insertion + " "
        let mention = ComposerPersonMention(
            profile: profile,
            mentionText: mentionText,
            range: TextRange(location: location, length: (mentionText as NSString).length)
        )
        return (updatedText, mention)
    }
}
