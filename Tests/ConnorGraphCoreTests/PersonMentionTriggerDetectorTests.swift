import Foundation
import Testing
import ConnorGraphCore

@Test func personMentionTriggerDetectsAtBeginningWithEmptyQuery() throws {
    let trigger = try #require(PersonMentionTriggerDetector().trigger(in: "@", selectedRange: NSRange(location: 1, length: 0)))

    #expect(trigger.query == "")
    #expect(trigger.range == NSRange(location: 0, length: 1))
}

@Test func personMentionTriggerDetectsChineseQueryAfterBoundary() throws {
    let text = "请问 @段"
    let trigger = try #require(PersonMentionTriggerDetector().trigger(in: text, selectedRange: NSRange(location: (text as NSString).length, length: 0)))

    #expect(trigger.query == "段")
    #expect(trigger.range == NSRange(location: 3, length: 2))
}

@Test func personMentionTriggerRejectsAtWithoutBoundary() {
    let text = "abc@段"
    let trigger = PersonMentionTriggerDetector().trigger(in: text, selectedRange: NSRange(location: (text as NSString).length, length: 0))

    #expect(trigger == nil)
}

@Test func personMentionTriggerRejectsQueryAfterWhitespace() {
    let text = "@段 磊"
    let trigger = PersonMentionTriggerDetector().trigger(in: text, selectedRange: NSRange(location: (text as NSString).length, length: 0))

    #expect(trigger == nil)
}

@Test func personMentionTriggerRejectsSelectionRange() {
    let trigger = PersonMentionTriggerDetector().trigger(in: "@段", selectedRange: NSRange(location: 1, length: 1))

    #expect(trigger == nil)
}

@Test func personMentionTriggerDetectsAfterChinesePunctuationAndSpace() throws {
    let text = "你好， @段"
    let trigger = try #require(PersonMentionTriggerDetector().trigger(in: text, selectedRange: NSRange(location: (text as NSString).length, length: 0)))

    #expect(trigger.query == "段")
    #expect(trigger.range == NSRange(location: 4, length: 2))
}

@Test func personMentionSearchKeepsSameDisplayNameDifferentIDsDistinct() {
    let profiles = [
        PersonProfile(id: ContactID(rawValue: "person-one"), displayName: "王强", emails: [ContactEmailAddress(email: "one@example.com")]),
        PersonProfile(id: ContactID(rawValue: "person-two"), displayName: "王强", emails: [ContactEmailAddress(email: "two@example.com")]),
        PersonProfile(id: ContactID(rawValue: "person-deleted"), displayName: "王强", status: .deleted)
    ]

    let results = PersonMentionSearch().search(query: "王", profiles: profiles, limit: 8)

    #expect(results.map(\.id) == [ContactID(rawValue: "person-one"), ContactID(rawValue: "person-two")])
}

@Test func composerPersonMentionTextRewriterReplacesTriggerAndTracksMentionRange() throws {
    let text = "请问 @du"
    let trigger = try #require(PersonMentionTriggerDetector().trigger(in: text, selectedRange: NSRange(location: (text as NSString).length, length: 0)))
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强",
        status: .active,
        memoryEntityID: "memory-person-duan"
    )

    let replacement = try ComposerPersonMentionTextRewriter().replace(trigger: trigger, in: text, with: profile)

    #expect(replacement.text == "请问 @段磊强 ")
    #expect(replacement.selectedRange == NSRange(location: (replacement.text as NSString).length, length: 0))
    #expect(replacement.mention.personID == ContactID(rawValue: "person-duan-leiqiang"))
    #expect(replacement.mention.mentionText == "@段磊强")
    #expect(replacement.mention.range == TextRange(location: 3, length: ("@段磊强" as NSString).length))
    #expect(replacement.mention.memoryEntityID == "memory-person-duan")
}
