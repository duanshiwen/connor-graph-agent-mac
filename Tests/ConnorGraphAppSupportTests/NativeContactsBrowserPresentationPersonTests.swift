import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Native Contacts Browser Person Presentation Tests")
struct NativeContactsBrowserPresentationPersonTests {
    @Test func profilesWithoutContactMethodsAppearInContactsList() {
        let profile = PersonProfile(id: ContactID(rawValue: "person-no-contact"), displayName: "小王")

        let presentation = NativeContactsBrowserPresentation.build(profiles: [profile])

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows.first?.id == profile.id)
        #expect(presentation.rows.first?.displayName == "小王")
        #expect(presentation.rows.first?.subtitle == "暂无联系方式")
        #expect(presentation.emptyMessage == nil)
    }

    @Test func profileRowSubtitleUsesFallbackOrder() {
        let email = PersonProfile(id: ContactID(rawValue: "email"), displayName: "Email", emails: [ContactEmailAddress(email: "email@example.com")])
        let org = PersonProfile(id: ContactID(rawValue: "org"), displayName: "Org", organizationName: "Connor Labs", jobTitle: "Designer")
        let notes = PersonProfile(id: ContactID(rawValue: "notes"), displayName: "Notes", notes: "朋友的朋友")
        let empty = PersonProfile(id: ContactID(rawValue: "empty"), displayName: "Empty")

        let rows = NativeContactsBrowserPresentation.build(profiles: [email, org, notes, empty]).rows
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id.rawValue, $0.subtitle) })

        #expect(byID["email"] == "email@example.com")
        #expect(byID["org"] == "Designer · Connor Labs")
        #expect(byID["notes"] == "朋友的朋友")
        #expect(byID["empty"] == "暂无联系方式")
    }

    @Test func profileSearchMatchesAliasesContactMethodsAndNotes() {
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-search"),
            displayName: "Alice Wang",
            aliases: ["小艾"],
            emails: [ContactEmailAddress(email: "alice@example.com")],
            phones: [PersonPhoneNumber(number: "13800000000")],
            organizationName: "Connor Labs",
            jobTitle: "Designer",
            notes: "杭州朋友"
        )

        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "alice").rows.map(\.id) == [profile.id])
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "小艾").rows.map(\.id) == [profile.id])
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "example").rows.map(\.id) == [profile.id])
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "138").rows.map(\.id) == [profile.id])
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "Connor").rows.map(\.id) == [profile.id])
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "杭州").rows.map(\.id) == [profile.id])
    }

    @Test func inactiveProfilesAreHiddenByDefaultButPendingProfilesAppear() {
        let active = PersonProfile(id: ContactID(rawValue: "active"), displayName: "Active", status: .active)
        let pending = PersonProfile(id: ContactID(rawValue: "pending"), displayName: "Pending", status: .pending)
        let merged = PersonProfile(id: ContactID(rawValue: "merged"), displayName: "Merged", status: .merged, mergedIntoID: active.id)
        let deleted = PersonProfile(id: ContactID(rawValue: "deleted"), displayName: "Deleted", status: .deleted)

        let rows = NativeContactsBrowserPresentation.build(profiles: [deleted, merged, pending, active]).rows

        #expect(rows.map(\.id) == [active.id, pending.id])
    }

    @Test func emptyMessageDistinguishesNoContactsFromNoMatches() {
        #expect(NativeContactsBrowserPresentation.build(profiles: []).emptyMessage == "暂无联系人")

        let profile = PersonProfile(id: ContactID(rawValue: "person"), displayName: "小王")
        #expect(NativeContactsBrowserPresentation.build(profiles: [profile], query: "zzz").emptyMessage == "没有匹配的联系人")
    }
}
