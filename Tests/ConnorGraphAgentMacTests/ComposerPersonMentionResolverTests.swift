import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Test func composerPersonMentionResolverAppendsMentionWithPersonID() {
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强",
        status: .active,
        memoryEntityID: "memory-person-duan"
    )
    let resolver = ComposerPersonMentionResolver()

    let result = resolver.appendingMention(profile: profile, to: "请整理")
    let references = resolver.personReferences(in: result.text, mentions: [result.mention])

    #expect(result.text == "请整理 @段磊强 ")
    #expect(result.mention.personID == ContactID(rawValue: "person-duan-leiqiang"))
    #expect(references == [PersonReference(profile: profile, mentionText: "@段磊强")])
}

@Test func composerPersonMentionResolverInvalidatesEditedMentionText() {
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强"
    )
    let resolver = ComposerPersonMentionResolver()
    let result = resolver.appendingMention(profile: profile, to: "请整理")
    let editedText = result.text.replacingOccurrences(of: "@段磊强", with: "@段磊")

    let references = resolver.personReferences(in: editedText, mentions: [result.mention])

    #expect(references.isEmpty)
}

@Test func composerPersonMentionResolverKeepsSameDisplayNameDifferentIDsDistinct() {
    let first = PersonProfile(id: ContactID(rawValue: "person-one"), displayName: "王强")
    let second = PersonProfile(id: ContactID(rawValue: "person-two"), displayName: "王强")
    let resolver = ComposerPersonMentionResolver()
    let firstResult = resolver.appendingMention(profile: first, to: "找")
    let secondResult = resolver.appendingMention(profile: second, to: firstResult.text)

    let references = resolver.personReferences(in: secondResult.text, mentions: [firstResult.mention, secondResult.mention])

    #expect(references.map(\.personID) == [ContactID(rawValue: "person-one"), ContactID(rawValue: "person-two")])
    #expect(references.allSatisfy { $0.displayName == "王强" })
}

@Test func composerPersonMentionResolverDeduplicatesRepeatedSamePersonReferences() {
    let profile = PersonProfile(id: ContactID(rawValue: "person-one"), displayName: "王强")
    let resolver = ComposerPersonMentionResolver()
    let first = resolver.appendingMention(profile: profile, to: "找")
    let second = resolver.appendingMention(profile: profile, to: first.text)

    let references = resolver.personReferences(in: second.text, mentions: [first.mention, second.mention])

    #expect(references.map(\.personID) == [ContactID(rawValue: "person-one")])
}
