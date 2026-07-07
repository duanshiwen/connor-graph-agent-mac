import Foundation
import Testing
import ConnorGraphCore

@Suite("Person Relationship Domain Tests")
struct PersonRelationshipDomainTests {
    @Test func personProfileEndpointRequiresPersonID() {
        let personID = ContactID(rawValue: "person-duan-fuqiang")
        let endpoint = PersonRelationshipEndpoint.personProfile(
            personID,
            memoryEntityID: "l4-entity:person-duan-fuqiang",
            memoryStableKey: "person-duan-fuqiang"
        )

        #expect(endpoint.kind == .personProfile)
        #expect(endpoint.personID == personID)
        #expect(endpoint.protectedIdentityAnchor == nil)
        #expect(endpoint.memoryEntityID == "l4-entity:person-duan-fuqiang")
        #expect(endpoint.memoryStableKey == "person-duan-fuqiang")
        #expect(endpoint.isCurrentUser == false)
    }

    @Test func currentUserEndpointUsesProtectedAnchorWithoutPersonID() {
        let endpoint = PersonRelationshipEndpoint.currentUser()

        #expect(endpoint.kind == .currentUser)
        #expect(endpoint.personID == nil)
        #expect(endpoint.protectedIdentityAnchor == PersonRelationshipEndpoint.currentUserProtectedIdentityAnchor)
        #expect(endpoint.memoryEntityID == PersonRelationshipEndpoint.currentUserMemoryEntityID)
        #expect(endpoint.memoryStableKey == PersonRelationshipEndpoint.currentUserMemoryStableKey)
        #expect(endpoint.isCurrentUser)
    }

    @Test func currentUserDetectionAcceptsCompatibleAnchorMetadata() {
        let endpoint = PersonRelationshipEndpoint(
            kind: .personProfile,
            personID: ContactID(rawValue: "person-legacy-current-user"),
            protectedIdentityAnchor: "current_user",
            memoryEntityID: nil,
            memoryStableKey: nil
        )

        #expect(endpoint.isCurrentUser)
    }

    @Test func relationshipCodableRoundTrips() throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let relationship = PersonRelationship(
            id: "relationship-1",
            source: .personProfile(ContactID(rawValue: "person-zhang-xia")),
            target: .currentUser(),
            kind: .parentOf,
            customKindLabel: "妈妈",
            note: "家庭关系",
            evidenceText: "张霞是我妈妈。",
            confidence: 1.0,
            status: .active,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(relationship)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(PersonRelationship.self, from: data)

        #expect(decoded == relationship)
        #expect(decoded.target.isCurrentUser)
    }

    @Test func relationshipKindDisplayTitleUsesCustomLabelWhenPresent() {
        let relationship = PersonRelationship(
            source: .personProfile(ContactID(rawValue: "person-zhang-xia")),
            target: .currentUser(),
            kind: .custom,
            customKindLabel: "妈妈"
        )

        #expect(relationship.displayKindTitle == "妈妈")
    }

    @Test func currentUserEndpointDefaultDisplayTitleIsUserFacing() {
        #expect(PersonRelationshipEndpoint.currentUser().fallbackDisplayTitle == "我（当前用户）")
    }
}
