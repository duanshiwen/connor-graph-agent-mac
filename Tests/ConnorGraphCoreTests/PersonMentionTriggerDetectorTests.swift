import Foundation
import Testing
import ConnorGraphCore

@Suite("Person Mention Trigger Detector Tests")
struct PersonMentionTriggerDetectorTests {
    @Test func detectsAtMentionAtStartOfInput() {
        let detector = PersonMentionTriggerDetector()
        let text = "@张"

        let trigger = detector.trigger(in: text, selectedRange: NSRange(location: text.utf16.count, length: 0))

        #expect(trigger?.query == "张")
        #expect(trigger?.range.location == 0)
        #expect(trigger?.range.length == 2)
    }

    @Test func detectsAtMentionAfterWhitespace() {
        let detector = PersonMentionTriggerDetector()
        let text = "请问 @小王"

        let trigger = detector.trigger(in: text, selectedRange: NSRange(location: text.utf16.count, length: 0))

        #expect(trigger?.query == "小王")
    }

    @Test func doesNotTriggerInsideEmailAddress() {
        let detector = PersonMentionTriggerDetector()
        let text = "a@example.com"

        let trigger = detector.trigger(in: text, selectedRange: NSRange(location: 3, length: 0))

        #expect(trigger == nil)
    }

    @Test func endsMentionAtWhitespace() {
        let detector = PersonMentionTriggerDetector()
        let text = "@小王 你好"

        let trigger = detector.trigger(in: text, selectedRange: NSRange(location: 3, length: 0))

        #expect(trigger?.query == "小王")
        #expect(trigger?.range.length == 3)
    }

    @Test func selectedPersonMentionReplacesTriggerText() throws {
        let trigger = PersonMentionTrigger(query: "小", range: NSRange(location: 2, length: 2))
        let profile = PersonProfile(id: ContactID(rawValue: "person-wang"), displayName: "小王")

        let result = try PersonMentionTextRewriter().replace(trigger: trigger, in: "问 @小", with: profile)

        #expect(result.text == "问 @小王 ")
        #expect(result.mention.personID == profile.id)
        #expect(result.mention.displayName == "小王")
        #expect(result.mention.insertedText == "@小王")
    }

    @Test func mentionSearchResolvesMergedSourceNameToTargetProfile() {
        let targetID = ContactID(rawValue: "person-target")
        let source = PersonProfile(id: ContactID(rawValue: "person-source"), displayName: "小王", status: .merged, mergedIntoID: targetID)
        let target = PersonProfile(id: targetID, displayName: "王诗闻")

        let results = PersonMentionSearch().search(query: "小王", profiles: [source, target])

        #expect(results.map(\.id) == [targetID])
    }

    @Test func mentionSearchExcludesDeletedAndMergedProfiles() {
        let active = PersonProfile(id: ContactID(rawValue: "person-active"), displayName: "小王")
        let deleted = PersonProfile(id: ContactID(rawValue: "person-deleted"), displayName: "小李", status: .deleted)
        let merged = PersonProfile(id: ContactID(rawValue: "person-merged"), displayName: "小张", status: .merged, mergedIntoID: active.id)

        let results = PersonMentionSearch().search(query: "小", profiles: [deleted, active, merged])

        #expect(results.map(\.id) == [active.id])
    }

    @Test func mentionSearchMatchesNotesPhonesAndAddresses() {
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-duan"),
            displayName: "段福强",
            phones: [PersonPhoneNumber(number: "13800000000")],
            addresses: [PersonPostalAddress(value: "杭州西湖区")],
            notes: "饼叔团队相关联系人"
        )
        let search = PersonMentionSearch()

        #expect(search.search(query: "饼叔团队", profiles: [profile]).map(\.id) == [profile.id])
        #expect(search.search(query: "138", profiles: [profile]).map(\.id) == [profile.id])
        #expect(search.search(query: "西湖", profiles: [profile]).map(\.id) == [profile.id])
    }
}
