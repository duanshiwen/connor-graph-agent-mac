import Foundation
import Testing
import ConnorGraphCore

@Suite("Person Profile Domain Tests")
struct PersonProfileDomainTests {
    @Test func personProfileCanExistWithoutContactMethods() {
        let profile = PersonProfile(displayName: "小王")

        #expect(profile.displayName == "小王")
        #expect(profile.emails.isEmpty)
        #expect(profile.phones.isEmpty)
        #expect(profile.addresses.isEmpty)
        #expect(profile.status == .active)
        #expect(profile.contactSubtitle == "暂无联系方式")
    }

    @Test func personProfileStatusCodableRoundTrips() throws {
        let statuses: [PersonProfileStatus] = [.active, .pending, .merged, .deleted]
        let data = try JSONEncoder().encode(statuses)
        let decoded = try JSONDecoder().decode([PersonProfileStatus].self, from: data)

        #expect(decoded == statuses)
    }

    @Test func personProfileSupportsLifecycleStatusesAndMergeTarget() {
        let target = ContactID(rawValue: "person-target")
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-source"),
            displayName: "小闻",
            status: .merged,
            mergedIntoID: target
        )

        #expect(profile.status == .merged)
        #expect(profile.mergedIntoID == target)
        #expect(profile.isActiveForDefaultContext == false)
    }

    @Test func contactRecordConvertsToPersonProfile() {
        let record = ContactRecord(
            id: ContactID(rawValue: "contact-1"),
            givenName: "Alice",
            familyName: "Wang",
            organizationName: "Connor Labs",
            emails: [ContactEmailAddress(label: "work", email: "alice@example.com")],
            source: "test"
        )

        let profile = PersonProfile(contactRecord: record, now: Date(timeIntervalSince1970: 100))

        #expect(profile.id == record.id)
        #expect(profile.displayName == "Alice Wang")
        #expect(profile.givenName == "Alice")
        #expect(profile.familyName == "Wang")
        #expect(profile.organizationName == "Connor Labs")
        #expect(profile.emails == record.emails)
        #expect(profile.status == .active)
    }

    @Test func personProfileConvertsToContactRecord() {
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-1"),
            displayName: "Alice Wang",
            givenName: "Alice",
            familyName: "Wang",
            emails: [ContactEmailAddress(label: "work", email: "alice@example.com")],
            organizationName: "Connor Labs",
            source: "person-registry"
        )

        let record = profile.contactRecord

        #expect(record.id == profile.id)
        #expect(record.givenName == "Alice")
        #expect(record.familyName == "Wang")
        #expect(record.organizationName == "Connor Labs")
        #expect(record.emails == profile.emails)
        #expect(record.source == "person-registry")
    }

    @Test func contactSubtitleUsesUsefulFallbackOrder() {
        let emailProfile = PersonProfile(displayName: "A", emails: [ContactEmailAddress(label: nil, email: "a@example.com")])
        let orgProfile = PersonProfile(displayName: "B", organizationName: "Connor Labs", jobTitle: "Designer")
        let noteProfile = PersonProfile(displayName: "C", notes: "朋友的朋友")
        let emptyProfile = PersonProfile(displayName: "D")

        #expect(emailProfile.contactSubtitle == "a@example.com")
        #expect(orgProfile.contactSubtitle == "Designer · Connor Labs")
        #expect(noteProfile.contactSubtitle == "朋友的朋友")
        #expect(emptyProfile.contactSubtitle == "暂无联系方式")
    }
}
