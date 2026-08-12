import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
struct PersonRelationshipPresentationTests {
    @Test func presentationIncludesRelationshipsWhereSelectedPersonIsSource() {
        let zhangXia = ContactID(rawValue: "person-zhang-xia")
        let relationship = PersonRelationship(
            id: "rel-1",
            source: .personProfile(zhangXia),
            target: .currentUser(),
            kind: .parentOf,
            customKindLabel: "妈妈"
        )

        let rows = PersonRelationshipPresentation.detailRows(
            for: zhangXia,
            personDisplayName: "张霞",
            relationships: [relationship],
            displayTitle: { endpoint in endpoint.isCurrentUser ? "我（当前用户）" : endpoint.fallbackDisplayTitle }
        )

        #expect(rows == [PersonRelationshipPresentation.DetailRow(
            relationship: relationship,
            kindTitle: "妈妈",
            directionText: "张霞 → 我（当前用户）"
        )])
    }

    @Test func presentationIncludesRelationshipsWhereSelectedPersonIsTarget() {
        let zhangXia = ContactID(rawValue: "person-zhang-xia")
        let shiwen = ContactID(rawValue: "person-shiwen")
        let relationship = PersonRelationship(
            id: "rel-1",
            source: .personProfile(zhangXia),
            target: .personProfile(shiwen),
            kind: .parentOf,
            customKindLabel: "妈妈",
            note: "从小带我长大"
        )

        let rows = PersonRelationshipPresentation.detailRows(
            for: shiwen,
            personDisplayName: "诗闻",
            relationships: [relationship],
            displayTitle: { endpoint in endpoint.personID == zhangXia ? "张霞" : endpoint.fallbackDisplayTitle }
        )

        #expect(rows == [PersonRelationshipPresentation.DetailRow(
            relationship: relationship,
            kindTitle: "妈妈",
            directionText: "张霞 → 诗闻",
            note: "从小带我长大"
        )])
    }

    @Test func presentationSkipsUnrelatedAndInactiveRelationships() {
        let selected = ContactID(rawValue: "person-selected")
        let active = PersonRelationship(id: "active", source: .personProfile(selected), target: .currentUser(), kind: .friendOf)
        let archived = PersonRelationship(id: "archived", source: .personProfile(selected), target: .currentUser(), kind: .friendOf, status: .archived)
        let unrelated = PersonRelationship(id: "unrelated", source: .personProfile(ContactID(rawValue: "person-a")), target: .personProfile(ContactID(rawValue: "person-b")), kind: .knows)

        let rows = PersonRelationshipPresentation.detailRows(
            for: selected,
            personDisplayName: "我",
            relationships: [archived, unrelated, active],
            displayTitle: { $0.fallbackDisplayTitle }
        )

        #expect(rows.count == 1)
        #expect(rows.first?.kindTitle == "朋友")
        #expect(rows.first?.directionText == "我 → 我（当前用户）")
    }
}
